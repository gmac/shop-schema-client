# frozen_string_literal: true

require_relative "request_transformer/transformation_map"
require_relative "request_transformer/result"

module ShopSchemaClient
  class RequestTransformer
    RESERVED_PREFIX = "___"
    TYPENAME_HINT = "#{RESERVED_PREFIX}typehint"
    EXTENSIONS_SCOPE = :extensions
    METAOBJECT_SCOPE = :metaobject
    NATIVE_SCOPE = :native

    def initialize(query, metafield_ns = "custom")
      @query = query
      @schema = query.schema
      @transform_map = TransformationMap.new
      @owner_types = @schema.possible_types(@schema.get_type("HasMetafields")).to_set
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

    def transform_scope(parent_type, input_selections, scope_type: NATIVE_SCOPE, extensions_ns: nil)
      results = input_selections.flat_map do |node|
        case node
        when GraphQL::Language::Nodes::Field
          if node.alias&.start_with?(RESERVED_PREFIX)
            raise ValidationError, "Field aliases starting with `#{RESERVED_PREFIX}` are reserved for system use."
          end

          @transform_map.field_breadcrumb(node.alias || node.name) do
            if scope_type == EXTENSIONS_SCOPE || scope_type == METAOBJECT_SCOPE
              build_metafield(parent_type, node, scope_type: scope_type, extensions_ns: extensions_ns)
            elsif scope_type == NATIVE_SCOPE && node.name == "extensions" && @owner_types.include?(parent_type)
              next_type = parent_type.get_field(node.name).type.unwrap
              @transform_map.apply_field_transform(FieldTransform.new("metafield_extensions"))
              transform_scope(next_type, node.selections, scope_type: EXTENSIONS_SCOPE, extensions_ns: node.alias || node.name)
            elsif node.selections&.any?
              next_type = parent_type.get_field(node.name).type.unwrap
              node.merge(selections: transform_scope(next_type, node.selections))
            else
              node
            end
          end

        when GraphQL::Language::Nodes::InlineFragment
          fragment_type = node.type.nil? ? parent_type : @schema.get_type(node.type.name)
          typed_scope(parent_type, fragment_type, scope_type) do
            if MetafieldTypeResolver.extensions_type?(fragment_type.graphql_name)
              transform_scope(fragment_type, node.selections, scope_type: EXTENSIONS_SCOPE, extensions_ns: extensions_ns)
            elsif MetafieldTypeResolver.metaobject_type?(fragment_type.graphql_name)
              GraphQL::Language::Nodes::InlineFragment.new(
                type: GraphQL::Language::Nodes::TypeName.new(name: "Metaobject"),
                selections: transform_scope(fragment_type, node.selections, scope_type: METAOBJECT_SCOPE, extensions_ns: extensions_ns),
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
                transform_scope(fragment_type, fragment_def.selections, scope_type: EXTENSIONS_SCOPE, extensions_ns: extensions_ns)
              elsif MetafieldTypeResolver.metaobject_type?(fragment_type.graphql_name)
                fragment_type_name = "Metaobject"
                transform_scope(fragment_type, fragment_def.selections, scope_type: METAOBJECT_SCOPE, extensions_ns: extensions_ns)
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
    end

    def typed_scope(parent_type, fragment_type, scope_type)
      if scope_type == NATIVE_SCOPE && parent_type.kind.abstract? && fragment_type != parent_type
        parent_types = @schema.possible_types(parent_type).map(&:graphql_name)
        fragment_types = @schema.possible_types(fragment_type).map(&:graphql_name)
        @transform_map.type_breadcrumb(parent_types & fragment_types) do
          results = Array.wrap(yield)
          results << GraphQL::Language::Nodes::Field.new(field_alias: TYPENAME_HINT, name: "__typename")
          results
        end
      else
        yield
      end
    end

    def build_metafield(parent_type, node, scope_type:, extensions_ns: nil)
      return build_typename(node, scope_type: scope_type, extensions_ns: extensions_ns) if node.name == "__typename"

      field = parent_type.get_field(node.name)
      metafield_attrs = field.directives.find { _1.graphql_name == "metafield" }&.arguments&.keyword_arguments
      return node unless metafield_attrs

      type_name = metafield_attrs[:type]
      is_list = MetafieldTypeResolver.list?(type_name)
      is_reference = MetafieldTypeResolver.reference?(type_name)
      field_alias = "#{scope_type == EXTENSIONS_SCOPE ? "#{RESERVED_PREFIX}#{extensions_ns}_" : ""}#{node.alias || node.name}"
      next_type = parent_type.get_field(node.name).type.unwrap

      selection = if is_reference && is_list
        @transform_map.apply_field_transform(FieldTransform.new(type_name))
        conn_node_type = next_type.get_field("nodes").type.unwrap
        conn_selections = node.selections.map do |conn_node|
          case conn_node.name
          when "edges"
            @transform_map.field_breadcrumb(conn_node.alias || conn_node.name) do
              edges_selections = conn_node.selections.map do |n|
                next n if n.name != "node"

                @transform_map.field_breadcrumb(n.alias || n.name) do
                  n.merge(selections: build_metafield_reference(conn_node_type, n.selections))
                end
              end
              conn_node.merge(selections: edges_selections)
            end
          when "nodes"
            @transform_map.field_breadcrumb(conn_node.alias || conn_node.name) do
              conn_node.merge(selections: build_metafield_reference(conn_node_type, conn_node.selections))
            end
          else
            conn_node
          end
        end

        GraphQL::Language::Nodes::Field.new(
          name: "references",
          arguments: node.arguments,
          selections: conn_selections,
        )
      elsif is_reference
        @transform_map.apply_field_transform(FieldTransform.new(type_name))
        GraphQL::Language::Nodes::Field.new(
          name: "reference",
          selections: build_metafield_reference(next_type, node.selections),
        )
      else
        @transform_map.apply_field_transform(
          FieldTransform.new(
            type_name,
            selections: extract_value_object_selection(node.selections).presence,
          )
        )
        GraphQL::Language::Nodes::Field.new(name: "value")
      end

      metafield_key = metafield_attrs[:key]
      metafield_key = "#{@metafield_ns}.#{metafield_key}" if scope_type == EXTENSIONS_SCOPE
      GraphQL::Language::Nodes::Field.new(
        field_alias: field_alias,
        name: scope_type == EXTENSIONS_SCOPE ? "metafield" : "field",
        arguments: [GraphQL::Language::Nodes::Argument.new(name: "key", value: metafield_key)],
        selections: Array.wrap(selection),
      )
    end

    def build_metafield_reference(reference_type, input_selections)
      if MetafieldTypeResolver.metaobject_type?(reference_type.graphql_name)
        [
          GraphQL::Language::Nodes::InlineFragment.new(
            type: GraphQL::Language::Nodes::TypeName.new(name: "Metaobject"),
            selections: transform_scope(reference_type, input_selections, scope_type: METAOBJECT_SCOPE),
          )
        ]
      else
        [
          GraphQL::Language::Nodes::InlineFragment.new(
            type: GraphQL::Language::Nodes::TypeName.new(name: reference_type.graphql_name),
            selections: transform_scope(reference_type, input_selections),
          )
        ]
      end
    end

    def build_typename(node, scope_type:, extensions_ns: nil)
      field_name = node.alias || node.name
      case scope_type
      when EXTENSIONS_SCOPE
        @transform_map.apply_field_transform(FieldTransform.new("extensions_typename"))
        return GraphQL::Language::Nodes::Field.new(
          field_alias: "#{RESERVED_PREFIX}#{extensions_ns}_#{field_name}",
          name: "__typename", # transform parent typename: Product -> ProductExtensions
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
