# frozen_string_literal: true

require_relative "request_transformer/transformation_map"
require_relative "request_transformer/result"

module ShopSchemaClient
  class RequestTransformer
    GQL_TYPENAME = "__typename"
    RESERVED_PREFIX = "___"
    TYPENAME_HINT = "#{RESERVED_PREFIX}typehint"
    CUSTOM_SCOPE_TRANSFORM = "custom_scope"
    EXTENSIONS_SCOPE = :extensions
    METAOBJECT_SCOPE = :metaobject
    NATIVE_SCOPE = :native

    def initialize(query, metafield_ns = "custom")
      @query = query
      @schema = query.schema
      @transform_map = TransformationMap.new
      @owner_types = @schema.possible_types(@schema.get_type("HasMetafields")).to_set
      @root_ext_name = MetafieldTypeResolver.extensions_typename(@schema.query.graphql_name)
      @metafield_ns = metafield_ns
      @new_fragments = {}
    end

    def perform
      op = @query.selected_operation
      parent_type = @query.root_type_for_operation(op.operation_type)
      op = op.merge(selections: transform_scope(parent_type, op.selections))
      document = GraphQL::Language::Nodes::Document.new(definitions: [op, *@new_fragments.values])
      Result.new(document, @transform_map)
    end

    private

    def transform_scope(parent_type, input_selections, scope_type: NATIVE_SCOPE, scope_ns: nil)
      results = input_selections.flat_map do |node|
        case node
        when GraphQL::Language::Nodes::Field
          if node.alias&.start_with?(RESERVED_PREFIX)
            raise ValidationError, "Field aliases starting with `#{RESERVED_PREFIX}` are reserved for system use"
          end

          @transform_map.field_breadcrumb(node) do
            if scope_type == NATIVE_SCOPE && node.name == "extensions" && (parent_type == @schema.query || @owner_types.include?(parent_type))
              @transform_map.apply_field_transform(FieldTransform.new(CUSTOM_SCOPE_TRANSFORM))
              custom_scope(node) do
                next_type = parent_type.get_field(node.name).type.unwrap
                transform_scope(next_type, node.selections, scope_type: EXTENSIONS_SCOPE, scope_ns: node.alias || node.name)
              end
            elsif scope_type == METAOBJECT_SCOPE && node.name == "system"
              @transform_map.apply_field_transform(FieldTransform.new(CUSTOM_SCOPE_TRANSFORM))
              custom_scope(node) do
                next_type = parent_type.get_field(node.name).type.unwrap
                transform_scope(next_type, node.selections, scope_ns: node.alias || node.name)
              end
            elsif scope_type == EXTENSIONS_SCOPE && parent_type.graphql_name == @root_ext_name
              build_metaobject_query(parent_type, node, scope_ns: scope_ns)
            elsif scope_type == EXTENSIONS_SCOPE || scope_type == METAOBJECT_SCOPE
              build_metafield(parent_type, node, scope_type: scope_type, scope_ns: scope_ns)
            else
              if scope_ns
                node = node.merge(alias: "#{RESERVED_PREFIX}#{scope_ns}_#{node.alias || node.name}")
              end
              if node.selections&.any?
                next_type = parent_type.get_field(node.name).type.unwrap
                node = node.merge(selections: transform_scope(next_type, node.selections))
              end
              node
            end
          end

        when GraphQL::Language::Nodes::InlineFragment
          fragment_type = node.type.nil? ? parent_type : @schema.get_type(node.type.name)
          typed_scope(parent_type, fragment_type, scope_type) do
            if MetafieldTypeResolver.extensions_type?(fragment_type.graphql_name)
              transform_scope(fragment_type, node.selections, scope_type: EXTENSIONS_SCOPE, scope_ns: scope_ns)
            elsif MetafieldTypeResolver.metaobject_type?(fragment_type.graphql_name)
              GraphQL::Language::Nodes::InlineFragment.new(
                type: GraphQL::Language::Nodes::TypeName.new(name: "Metaobject"),
                selections: transform_scope(fragment_type, node.selections, scope_type: METAOBJECT_SCOPE, scope_ns: scope_ns),
              )
            else
              GraphQL::Language::Nodes::InlineFragment.new(
                type: GraphQL::Language::Nodes::TypeName.new(name: fragment_type.graphql_name),
                selections: transform_scope(fragment_type, node.selections),
              )
            end
          end

        when GraphQL::Language::Nodes::FragmentSpread
          fragment_def = @query.fragments[node.name]
          fragment_type = @schema.get_type(fragment_def.type.name)
          typed_scope(parent_type, fragment_type, scope_type) do
            unless @new_fragments[node.name]
              fragment_type_name = fragment_type.graphql_name
              fragment_selections = if MetafieldTypeResolver.extensions_type?(fragment_type.graphql_name)
                fragment_type_name = fragment_type_name.sub(MetafieldTypeResolver::EXTENSIONS_TYPE_SUFFIX, "")
                transform_scope(fragment_type, fragment_def.selections, scope_type: EXTENSIONS_SCOPE, scope_ns: scope_ns)
              elsif MetafieldTypeResolver.metaobject_type?(fragment_type.graphql_name)
                fragment_type_name = "Metaobject"
                transform_scope(fragment_type, fragment_def.selections, scope_type: METAOBJECT_SCOPE, scope_ns: scope_ns)
              else
                transform_scope(fragment_type, fragment_def.selections)
              end

              @new_fragments[node.name] = fragment_def.merge(
                type: GraphQL::Language::Nodes::TypeName.new(name: fragment_type_name),
                selections: fragment_selections,
              )
            end

            node
          end
        end
      end

      compact_typehints(results)
      results
    end

    def custom_scope(node)
      selections = Array.wrap(yield)
      # custom scopes prepend a placeholder to reserve their position in the final selection order
      selections.prepend(GraphQL::Language::Nodes::Field.new(field_alias: node.alias || node.name, name: GQL_TYPENAME))
      selections
    end

    def typed_scope(parent_type, fragment_type, scope_type)
      parent_types = @schema.possible_types(parent_type).map(&:graphql_name)
      fragment_types = @schema.possible_types(fragment_type).map(&:graphql_name)

      if scope_type == NATIVE_SCOPE && parent_type.kind.abstract? && fragment_type != parent_type
        @transform_map.type_breadcrumb(parent_types & fragment_types) do
          results = Array.wrap(yield)
          results << GraphQL::Language::Nodes::Field.new(field_alias: TYPENAME_HINT, name: GQL_TYPENAME)
          results
        end
      elsif scope_type == METAOBJECT_SCOPE && MetafieldTypeResolver.mixed_metaobject_type?(parent_type.graphql_name)
        @transform_map.type_breadcrumb(parent_types & fragment_types, map_all_fields: true) do
          results = Array.wrap(yield)
          results << GraphQL::Language::Nodes::Field.new(field_alias: TYPENAME_HINT, name: "type")
          results
        end
      else
        yield
      end
    end

    def build_connection_selections(conn_type, conn_node)
      conn_node_type = conn_type.get_field("nodes").type.unwrap
      conn_node.selections.map do |node|
        @transform_map.field_breadcrumb(node) do
          case node.name
          when "edges"
            edges_selections = node.selections.map do |n|
              @transform_map.field_breadcrumb(n) do
                case n.name
                when "node"
                  n.merge(selections: yield(conn_node_type, n.selections))
                when GQL_TYPENAME
                  edge_type = conn_type.get_field("edges").type.unwrap
                  @transform_map.apply_field_transform(FieldTransform.new("static_typename", value: edge_type.graphql_name))
                  n
                else
                  n
                end
              end
            end
            node.merge(selections: edges_selections)
          when "nodes"
            node.merge(selections: yield(conn_node_type, node.selections))
          when GQL_TYPENAME
            @transform_map.apply_field_transform(FieldTransform.new("static_typename", value: conn_type.graphql_name))
            node
          else
            node
          end
        end
      end
    end

    def build_metaobject_query(parent_type, node, scope_ns: nil)
      return build_typename(parent_type, node, scope_type: EXTENSIONS_SCOPE, scope_ns: scope_ns) if node.name == GQL_TYPENAME

      field = parent_type.get_field(node.name)
      metaobject_attrs = field.directives.find { _1.graphql_name == "metaobject" }&.arguments&.keyword_arguments
      return node unless metaobject_attrs

      selections = build_connection_selections(field.type.unwrap, node) do |conn_node_type, conn_node_selections|
        transform_scope(conn_node_type, conn_node_selections, scope_type: METAOBJECT_SCOPE)
      end

      GraphQL::Language::Nodes::Field.new(
        field_alias: "#{RESERVED_PREFIX}#{scope_ns}_#{node.alias || node.name}",
        name: "metaobjects",
        arguments: [*node.arguments, GraphQL::Language::Nodes::Argument.new(name: "type", value: metaobject_attrs[:type])],
        selections: selections,
      )
    end

    def build_metafield(parent_type, node, scope_type:, scope_ns: nil)
      return build_typename(parent_type, node, scope_type: scope_type, scope_ns: scope_ns) if node.name == GQL_TYPENAME

      field = parent_type.get_field(node.name)
      metafield_attrs = field.directives.find { _1.graphql_name == "metafield" }&.arguments&.keyword_arguments
      return node unless metafield_attrs

      type_name = metafield_attrs[:type]
      is_list = MetafieldTypeResolver.list?(type_name)
      is_reference = MetafieldTypeResolver.reference?(type_name)
      field_alias = "#{scope_type == EXTENSIONS_SCOPE ? "#{RESERVED_PREFIX}#{scope_ns}_" : ""}#{node.alias || node.name}"

      selection = if is_reference && is_list
        @transform_map.apply_field_transform(FieldTransform.new(type_name))
        selections = build_connection_selections(field.type.unwrap, node) do |conn_node_type, conn_node_selections|
          build_metafield_reference(conn_node_type, conn_node_selections)
        end

        GraphQL::Language::Nodes::Field.new(
          name: "references",
          arguments: node.arguments,
          selections: selections,
        )
      elsif is_reference
        @transform_map.apply_field_transform(FieldTransform.new(type_name))
        GraphQL::Language::Nodes::Field.new(
          name: "reference",
          selections: build_metafield_reference(field.type.unwrap, node.selections),
        )
      else
        @transform_map.apply_field_transform(
          FieldTransform.new(
            type_name,
            selections: extract_value_object_selection(node.selections).presence,
          )
        )
        GraphQL::Language::Nodes::Field.new(name: "jsonValue")
      end

      GraphQL::Language::Nodes::Field.new(
        field_alias: field_alias,
        name: scope_type == EXTENSIONS_SCOPE ? "metafield" : "field",
        arguments: [GraphQL::Language::Nodes::Argument.new(name: "key", value: metafield_attrs[:key])],
        selections: Array.wrap(selection),
      )
    end

    def build_metafield_reference(reference_type, input_selections)
      result = if MetafieldTypeResolver.metaobject_type?(reference_type.graphql_name) ||
        MetafieldTypeResolver.mixed_metaobject_type?(reference_type.graphql_name)
        GraphQL::Language::Nodes::InlineFragment.new(
          type: GraphQL::Language::Nodes::TypeName.new(name: "Metaobject"),
          selections: transform_scope(reference_type, input_selections, scope_type: METAOBJECT_SCOPE),
        )
      else
        GraphQL::Language::Nodes::InlineFragment.new(
          type: GraphQL::Language::Nodes::TypeName.new(name: reference_type.graphql_name),
          selections: transform_scope(reference_type, input_selections),
        )
      end

      Array.wrap(result)
    end

    def build_typename(parent_type, node, scope_type:, scope_ns: nil)
      field_name = node.alias || node.name
      case scope_type
      when EXTENSIONS_SCOPE
        @transform_map.apply_field_transform(FieldTransform.new("static_typename", value: parent_type.graphql_name))
        return GraphQL::Language::Nodes::Field.new(
          field_alias: "#{RESERVED_PREFIX}#{scope_ns}_#{field_name}",
          name: GQL_TYPENAME, # transform parent typename: Product -> ProductExtensions
        )
      when METAOBJECT_SCOPE
        @transform_map.apply_field_transform(FieldTransform.new("metaobject_typename"))
        return GraphQL::Language::Nodes::Field.new(
          field_alias: field_name,
          name: "type", # transform object type: taco -> TacoMetaobject
        )
      else
        node
      end
    end

    # value types (Money, Volume, Dimension) are always concrete,
    # so can safely traverse fragment selections without type awareness.
    def extract_value_object_selection(selections, acc = [])
      selections.each do |node|
        case node
        when GraphQL::Language::Nodes::Field
          acc << [node.alias, node.name].tap(&:compact!).join(":")
        when GraphQL::Language::Nodes::InlineFragment
          extract_value_object_selection(node.selections, acc)
        when GraphQL::Language::Nodes::FragmentSpread
          extract_value_object_selection(@query.fragments[node.name].selections, acc)
        end
      end
      acc
    end

    def compact_typehints(results)
      typehint_node = nil
      results.reject! do |node|
        next false unless node.is_a?(GraphQL::Language::Nodes::Field) && node.alias == TYPENAME_HINT

        typehint_node = node
        true
      end
      results << typehint_node if typehint_node
      results
    end
  end
end
