# frozen_string_literal: true

module ShopSchemaClient
  class SchemaComposer
    class MetafieldDirective < GraphQL::Schema::Directive
      graphql_name "metafield"
      locations FIELD_DEFINITION
      argument :key, String, required: true
      argument :type, String, required: true
    end

    class MetaobjectDirective < GraphQL::Schema::Directive
      graphql_name "metaobject"
      locations FIELD_DEFINITION
      argument :type, String, required: true
    end

    attr_reader :schema_types

    def initialize(base_schema, catalog)
      @base_schema = base_schema
      @catalog = catalog

      introspection_names = @base_schema.introspection_system.types.keys
      @schema_types = @base_schema.types.reject! { |k, v| introspection_names.include?(k) }
      @metaobject_unions = {}
    end

    def perform
      query_name = @base_schema.query.graphql_name
      mutation_name = @base_schema.mutation.graphql_name

      @base_schema.possible_types(@schema_types["HasMetafields"]).each do |owner_type|
        build_owner_type_extensions(owner_type)
      end

      metaobject_queries = @catalog.metaobject_definitions.each_with_object({}) do |metaobject_def, memo|
        metaobject_type = build_metaobject(metaobject_def)
        connection_type = build_connection_type(metaobject_type)
        memo[metaobject_def] = connection_type
      end

      if metaobject_queries.any?
        build_root_query_extensions(@schema_types[query_name], metaobject_queries)
      end

      @metaobject_unions.each do |metaobject_union, is_list|
        metaobject_type = build_mixed_metaobject(metaobject_union)
        build_connection_type(metaobject_type) if is_list
      end

      builder = self
      Class.new(GraphQL::Schema) do
        use(GraphQL::Schema::Visibility)
        directive(MetafieldDirective)
        add_type_and_traverse(builder.schema_types.values, root: false)
        orphan_types(builder.schema_types.values.select { |t| t.respond_to?(:kind) && t.kind.object? })
        query(builder.schema_types[query_name])
        mutation(builder.schema_types[mutation_name])
        own_orphan_types.clear
      end
    end

    def type_for_metafield_definition(field_def)
      is_list = field_def.list?
      case field_def.type
      when "boolean"
        @schema_types["Boolean"]
      when "color", "list.color"
        type = build_color_metatype
        is_list ? type.to_list_type : type
      when "collection_reference", "list.collection_reference"
        is_list ? @schema_types["CollectionConnection"] : @schema_types["Collection"]
      when "company_reference", "list.company_reference"
        is_list ? @schema_types["CompanyConnection"] : @schema_types["Company"]
      when "customer_reference", "list.customer_reference"
        is_list ? @schema_types["CustomerConnection"] : @schema_types["Customer"]
      when "date_time", "list.date_time"
        type = @schema_types["DateTime"]
        is_list ? type.to_list_type : type
      when "date", "list.date"
        type = @schema_types["Date"]
        is_list ? type.to_list_type : type
      when "dimension", "list.dimension"
        type = build_dimension_metatype
        is_list ? type.to_list_type : type
      when "file_reference", "list.file_reference"
        type = @schema_types["File"]
        is_list ? build_connection_type(type) : type
      when "id"
        @schema_types["ID"]
      when "json"
        @schema_types["JSON"]
      when "language"
        @schema_types["LanguageCode"]
      when "link", "list.link"
        type = @schema_types["Link"]
        is_list ? type.to_list_type : type
      when "metaobject_reference", "list.metaobject_reference"
        if (object = field_def.linked_metaobject(@catalog))
          GraphQL::Schema::LateBoundType.new(
            is_list ? MetafieldTypeResolver.connection_typename(object.typename) : object.typename
          )
        else
          raise "Invalid #{field_def.type} for `#{field_def.key}`"
        end
      when "mixed_reference", "list.mixed_reference"
        if (union = field_def.linked_metaobject_union(@catalog))
          @metaobject_unions[union] ||= is_list
          GraphQL::Schema::LateBoundType.new(
            is_list ? MetafieldTypeResolver.connection_typename(union.typename) : union.typename
          )
        else
          raise "Invalid #{field_def.type} for `#{field_def.key}`"
        end
      when "money"
        @schema_types["MoneyV2"]
      when "multi_line_text_field"
        @schema_types["String"]
      when "number_decimal", "list.number_decimal"
        type = @schema_types["Float"]
        is_list ? type.to_list_type : type
      when "number_integer", "list.number_integer"
        type = @schema_types["Int"]
        is_list ? type.to_list_type : type
      when "order_reference"
        @schema_types["Order"]
      when "page_reference", "list.page_reference"
        is_list ? @schema_types["PageConnection"] : @schema_types["Page"]
      when "product_reference", "list.product_reference"
        is_list ? @schema_types["ProductConnection"] : @schema_types["Product"]
      when "product_taxonomy_value_reference", "list.product_taxonomy_value_reference"
        is_list ? @schema_types["TaxonomyValueConnection"] : @schema_types["TaxonomyValue"]
      when "rating", "list.rating"
        type = build_rating_metatype
        is_list ? type.to_list_type : type
      when "rich_text_field"
        build_rich_text_metatype
      when "single_line_text_field", "list.single_line_text_field"
        type = @schema_types["String"]
        is_list ? type.to_list_type : type
      when "url", "list.url"
        type = @schema_types["URL"]
        is_list ? type.to_list_type : type
      when "variant_reference", "list.variant_reference"
        is_list ? @schema_types["ProductVariantConnection"] : @schema_types["ProductVariant"]
      when "volume", "list.volume"
        type = build_volume_metatype
        is_list ? type.to_list_type : type
      when "weight", "list.weight"
        type = @schema_types["Weight"]
        is_list ? type.to_list_type : type
      else
        raise "Unknown metafield type `#{metafield_type}`"
      end
    end

    def build_root_query_extensions(query_type, metaobject_queries)
      extensions_typename = MetafieldTypeResolver.extensions_typename(query_type.graphql_name)
      builder = self

      @schema_types[extensions_typename] ||= begin
        extensions_type = Class.new(GraphQL::Schema::Object) do
          graphql_name(extensions_typename)
          description("Custom metaobject query extensions.")

          metaobject_queries.each do |metaobject_def, connection_type|
            field(
              metaobject_def.connection_field.to_sym,
              connection_type,
              null: true,
              description: "A paginated list of `#{metaobject_def.typename}` items.",
              connection: false,
            ) do |f|
              f.directive(MetaobjectDirective, type: metaobject_def.type)
              f.argument(:first, builder.schema_types["Int"], required: false)
              f.argument(:last, builder.schema_types["Int"], required: false)
              f.argument(:before, builder.schema_types["String"], required: false)
              f.argument(:after, builder.schema_types["String"], required: false)
            end
          end
        end

        query_type.field(
          :extensions,
          extensions_type,
          null: false,
          description: "Custom metaobject query extensions."
        )

        extensions_type
      end
    end

    def build_owner_type_extensions(owner_type)
      metafield_definitions = @catalog.metafields_for_type(owner_type.graphql_name)
      return unless metafield_definitions&.any?

      extensions_typename = MetafieldTypeResolver.extensions_typename(owner_type.graphql_name)
      return unless @schema_types[extensions_typename].nil?

      builder = self
      @schema_types[extensions_typename] = begin
        extensions_type = Class.new(GraphQL::Schema::Object) do
          graphql_name(extensions_typename)
          description("Metafield extensions for the `#{owner_type.graphql_name}` type.")

          metafield_definitions.each do |metafield_def|
            builder.build_object_metafield(metafield_def, self)
          end
        end

        owner_type.field(
          :extensions,
          extensions_type,
          null: false,
          description: "Custom metafield extensions.",
        )

        extensions_type
      end
    end

    # these metaobject keys are already restricted by the Shopify backend...
    RESERVED_METAOBJECT_KEYS = ["id", "handle", "system"].freeze

    def build_metaobject(metaobject_def)
      builder = self
      @schema_types[metaobject_def.typename] ||= Class.new(GraphQL::Schema::Object) do
        graphql_name(metaobject_def.typename)
        description(metaobject_def.description)
        field(:id, builder.schema_types["ID"], null: false)
        field(:handle, builder.schema_types["String"], null: false)
        field(:system, builder.schema_types["Metaobject"], null: false)

        metaobject_def.fields.each do |metafield_def|
          if RESERVED_METAOBJECT_KEYS.include?(metafield_def.key)
            raise ValidationError, "Metaobject key `#{metafield_def.key}` is reserved for system use"
          end

          builder.build_object_metafield(metafield_def, self)
        end
      end
    end

    def build_mixed_metaobject(metaobject_set)
      builder = self
      @schema_types[metaobject_set.typename] ||= Class.new(GraphQL::Schema::Union) do
        graphql_name(metaobject_set.typename)
        description("A mixed metaobject reference.")
        possible_types(*metaobject_set.metaobject_definitions.map { builder.build_metaobject(_1) })
      end
    end

    def build_object_metafield(metafield_def, owner)
      builder = self
      type = type_for_metafield_definition(metafield_def)
      owner.field(
        metafield_def.key.to_sym,
        type,
        description: metafield_def.description,
        connection: false,
      ) do |f|
        f.directive(MetafieldDirective, key: metafield_def.structured_key, type: metafield_def.type)
        if MetafieldTypeResolver.connection_type?(type.unwrap.graphql_name)
          f.argument(:first, builder.schema_types["Int"], required: false)
          f.argument(:last, builder.schema_types["Int"], required: false)
          f.argument(:before, builder.schema_types["String"], required: false)
          f.argument(:after, builder.schema_types["String"], required: false)
        end
      end
    end

    def build_connection_type(base_type)
      builder = self
      connection_type_name = MetafieldTypeResolver.connection_typename(base_type.graphql_name)
      @schema_types[base_type.edge_type.graphql_name] ||= base_type.edge_type
      @schema_types[connection_type_name] ||= Class.new(GraphQL::Schema::Object) do
        graphql_name(connection_type_name)
        field :edges, base_type.edge_type.to_non_null_type.to_list_type, null: false
        field :nodes, base_type.to_non_null_type.to_list_type, null: false
        field :page_info, builder.schema_types["PageInfo"], null: false
      end
    end

    def build_color_metatype
      @schema_types[MetafieldTypeResolver::COLOR_TYPENAME] ||= Class.new(GraphQL::Schema::Scalar) do
        graphql_name(MetafieldTypeResolver::COLOR_TYPENAME)
        description("A hexadecimal color code.")
      end
    end

    def build_dimension_metatype
      builder = self
      @schema_types[MetafieldTypeResolver::DIMENSION_TYPENAME] ||= Class.new(GraphQL::Schema::Object) do
        graphql_name(MetafieldTypeResolver::DIMENSION_TYPENAME)
        description("A dimensional measurement.")
        field :unit, builder.schema_types["String"]
        field :value, builder.schema_types["Float"]
      end
    end

    def build_rating_metatype
      builder = self
      @schema_types[MetafieldTypeResolver::RATING_TYPENAME] ||= Class.new(GraphQL::Schema::Object) do
        graphql_name(MetafieldTypeResolver::RATING_TYPENAME)
        description("A rating value.")
        field :max, builder.schema_types["Float"]
        field :min, builder.schema_types["Float"]
        field :value, builder.schema_types["Float"]
      end
    end

    def build_rich_text_metatype
      @schema_types[MetafieldTypeResolver::RICH_TEXT_TYPENAME] ||= Class.new(GraphQL::Schema::Scalar) do
        graphql_name(MetafieldTypeResolver::RICH_TEXT_TYPENAME)
        description("A parsed rich text data structure in JSON format.")
      end
    end

    def build_volume_metatype
      builder = self
      @schema_types[MetafieldTypeResolver::VOLUME_TYPENAME] ||= Class.new(GraphQL::Schema::Object) do
        graphql_name(MetafieldTypeResolver::VOLUME_TYPENAME)
        description("A volumetric measurement.")
        field :unit, builder.schema_types["String"]
        field :value, builder.schema_types["Float"]
      end
    end
  end
end
