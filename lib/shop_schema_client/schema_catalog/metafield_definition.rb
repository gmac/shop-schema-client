# frozen_string_literal: true

module ShopSchemaClient
  class SchemaCatalog
    METAFIELD_GRAPHQL_ATTRS = %|
      fragment MetafieldAttrs on MetafieldDefinition {
        key
        namespace
        ownerType
        description
        type { name }
        validations {
          name
          value
        }
      }
    |

    MetafieldDefinition = Struct.new(
      :key,
      :type,
      :namespace,
      :description,
      :validations,
      :owner_type,
      keyword_init: true
    ) do
      class << self
        def from_graphql(metafield_def)
          new(
            key: metafield_def["key"],
            type: metafield_def.dig("type", "name"),
            namespace: metafield_def["namespace"],
            description: metafield_def["description"],
            validations: metafield_def["validations"],
            owner_type: metafield_def["ownerType"],
          )
        end
      end

      def structured_key
        if namespace
          "#{namespace}.#{key}"
        else
          key
        end
      end

      def list?
        ShopSchemaClient::MetafieldTypeResolver.list?(type)
      end

      def reference?
        ShopSchemaClient::MetafieldTypeResolver.reference?(type)
      end

      def linked_metaobject(catalog)
        validation = validations.find { _1["name"] == "metaobject_definition_id" }
        catalog.metaobject_by_id(validation["value"]) if validation
      end

      def linked_metaobject_union(catalog)
        validation = validations.find { _1["name"] == "metaobject_definition_ids" }
        if validation
          validation = validation["value"]
          validation = JSON.parse(validation) if validation.is_a?(String)
          MetaobjectUnion.new(validation.map { catalog.metaobject_by_id(_1) })
        end
      end
    end
  end
end
