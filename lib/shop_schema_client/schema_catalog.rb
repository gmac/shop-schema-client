# frozen_string_literal: true

require_relative "schema_catalog/metafield_definition"
require_relative "schema_catalog/metaobject_definition"
require_relative "schema_catalog/metaobject_union"

module ShopSchemaClient
  class SchemaCatalog
    OWNER_TYPES = {
      "CartTransform" => "CARTTRANSFORM",
      "CustomerSegmentMember" => "CUSTOMER",
      "DiscountAutomaticNode" => "DISCOUNT",
      "DiscountCodeNode" => "DISCOUNT",
      "DiscountNode" => "DISCOUNT",
      "DraftOrder" => "DRAFTORDER",
      "GiftCardCreditTransaction" => "GIFT_CARD_TRANSACTION",
      "GiftCardDebitTransaction" => "GIFT_CARD_TRANSACTION",
      "Image" => "MEDIA_IMAGE",
      "ProductVariant" => "PRODUCTVARIANT",
    }.freeze

    def initialize
      @metafields_by_owner = {}
      @metaobjects_by_id = {}
    end

    def add_metafield(metafield)
      metafield = MetafieldDefinition.from_graphql(metafield) if metafield.is_a?(Hash)
      @metafields_by_owner[metafield.owner_type] ||= {}
      @metafields_by_owner[metafield.owner_type][metafield.key] = metafield
    end

    def add_metaobject(metaobject)
      metaobject = MetaobjectDefinition.from_graphql(metaobject) if metaobject.is_a?(Hash)
      @metaobjects_by_id[metaobject.id] = metaobject
    end

    def metaobject_definitions
      @metaobjects_by_id.values
    end

    def metaobject_by_id(id)
      @metaobjects_by_id[id]
    end

    def metafields_for_type(graphql_name)
      mapped_name = OWNER_TYPES.fetch(graphql_name, graphql_name.underscore.upcase)
      fields_for_owner = @metafields_by_owner[mapped_name]
      fields_for_owner ? fields_for_owner.values : []
    end

    OWNER_TYPE_ENUMS = [
      "PRODUCT",
      "PRODUCTVARIANT",
    ].freeze

    METAFIELD_DEFINITIONS_QUERY = %|
      query MetafieldDefs($after: String, $query: String, $owner_type: MetafieldOwnerType!) {
        app { id }
        results: metafieldDefinitions(first: 250, after: $after, query: $query, ownerType: $owner_type) {
          nodes { ...MetafieldAttrs }
          pageInfo {
            endCursor
            hasNextPage
          }
        }
      }
      #{METAFIELD_GRAPHQL_ATTRS}|

    METAOBJECT_DEFINITIONS_QUERY = %|
      query MetaobjectDefs($after: String) {
        app { id }
        results: metaobjectDefinitions(first: 250, after: $after) {
          nodes { ...MetaobjectAttrs }
          pageInfo {
            endCursor
            hasNextPage
          }
        }
      }
      #{METAOBJECT_GRAPHQL_ATTRS}|

    def load(client, namespace: "custom", owner_types: OWNER_TYPE_ENUMS)
      throttle_available = 1

      owner_types.each do |owner_type|
        throttle_available = paginated_fetch(
          client,
          METAFIELD_DEFINITIONS_QUERY,
          { owner_type: "PRODUCT" },
          throttle_available: throttle_available,
          request_cost: 0,
        ) do |nodes, app_id|
          ns = namespace == "$app" ? "app--#{app_id}" : namespace
          nodes.each do |node|
            add_metafield(node) if node["namespace"] == ns
          end
        end
      end

      paginated_fetch(
        client,
        METAOBJECT_DEFINITIONS_QUERY,
        throttle_available: throttle_available,
        request_cost: 50,
      ) do |nodes, app_id|
        app_ns = "app--#{app_id}"
        nodes.each do |node|
          if namespace == "$app"
            if node["type"].start_with?(app_ns)
              node["type"].gsub!(app_ns, "")
            else
              next
            end
          elsif node["type"].start_with?("app--")
            next
          end

          add_metaobject(node)
        end
      end
      self
    end

    private

    def paginated_fetch(client, query, variables = {}, request_cost: 0, throttle_available: 1)
      next_page = true
      next_cursor = nil
      throttle_restore = 100

      while next_page
        available = throttle_available - request_cost
        sleep (available.abs.to_f / throttle_restore) + 0.05 if available < 0

        result = client.fetch(query, variables: { after: next_cursor }.merge!(variables))
        if result["errors"]
          raise result["errors"].map { _1["message"] }.join(", ")
        else
          conn = result.dig("data", "results")
          yield(conn["nodes"], result.dig("data", "app", "id").split("/").pop.to_i)
          page_info = conn.dig("pageInfo")
          next_page = page_info["hasNextPage"]
          next_cursor = page_info["endCursor"]
        end

        cost = result.dig("extensions", "cost")
        request_cost = cost["requestedQueryCost"]
        throttle_available = cost.dig("throttleStatus", "currentlyAvailable")
        throttle_restore = cost.dig("throttleStatus", "restoreRate")
      end

      throttle_available
    end
  end
end
