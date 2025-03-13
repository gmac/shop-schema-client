# frozen_string_literal: true

require "pathname"

module ShopifyCustomDataGraphQL
  class Client
    INTROSPECTION_FIELDS = ["__schema", "__type", "__typename"].freeze

    class LruCache
      def initialize(max_bytesize)
        @data = {}
        @bytesizes = {}
        @current_bytesize = 0
        @max_bytesize = max_bytesize
        @prune_bytesize = max_bytesize - (max_bytesize * 0.2).to_i
      end

      def get(key)
        found = true
        value = @data.delete(key) { found = false }
        @data[key] = value if found
        value
      end

      def set(key, value, bytesize)
        @current_bytesize -= @bytesizes.delete(key).to_i
        @current_bytesize += bytesize
        @bytesizes[key] = bytesize
        @data[key] = value

        if @current_bytesize > @max_bytesize
          while @current_bytesize > @prune_bytesize
            @current_bytesize -= @bytesizes.delete(@data.shift[0]).to_i
          end
        end
        value
      end
    end

    def initialize(
      shop_url:,
      access_token:,
      api_version: "2025-01",
      app_context_id: nil,
      base_namespaces: nil,
      prefixed_namespaces: nil,
      file_store_path: nil,
      lru_max_bytesize: 5.megabytes,
      digest_class: Digest::MD5
    )
      @app_context_id = app_context_id
      @base_namespaces = base_namespaces
      @prefixed_namespaces = prefixed_namespaces
      @file_store_path = Pathname.new(file_store_path) if file_store_path
      @digest_class = digest_class

      if app_context_id
        @base_namespaces ||= ["$app"]
        @prefixed_namespaces ||= ["custom", "my_fields", "app--*"]
      else
        @base_namespaces ||= ["custom"]
        @prefixed_namespaces ||= ["my_fields", "app--*"]
      end

      @admin = AdminApiClient.new(
        shop_url: shop_url,
        access_token: access_token,
        api_version: api_version,
      )

      @lru = LruCache.new(lru_max_bytesize) if lru_max_bytesize > 0
      @on_cache_read = nil
      @on_cache_write = nil
    end

    def eager_load!
      schema
    end

    def schema(reload_custom_schema: false, reload_admin_schema: false)
      @schema = nil if reload_custom_schema || reload_admin_schema
      @schema ||= begin
        custom_schema = with_file_store(schema_file_name("custom", @app_context_id), force_reload: reload_custom_schema) do
          admin_schema = with_file_store(schema_file_name("admin"), force_reload: reload_admin_schema) do
            @admin.schema
          end

          admin_schema = GraphQL::Schema.from_definition(admin_schema) if admin_schema.is_a?(String)
          catalog = CustomDataCatalog.fetch(
            @admin,
            app_id: @app_context_id,
            base_namespaces: @base_namespaces,
            prefixed_namespaces: @prefixed_namespaces,
          )

          SchemaComposer.new(admin_schema, catalog).perform
        end

        custom_schema = GraphQL::Schema.from_definition(custom_schema) if custom_schema.is_a?(String)
        custom_schema
      end
    end

    def execute(query: nil, variables: nil, operation_name: nil)
      tracer = Tracer.new
      tracer.span("execute") do
        perform_query(query, operation_name, tracer) do |admin_query|
          @admin.fetch(admin_query, variables: variables)
        end
      end
    rescue ValidationError => e
      PreparedQuery::Result.new(
        query: query,
        tracer: tracer,
        result: { "errors" => e.errors },
      )
    end

    def on_cache_read(&block)
      raise ArgumentError, "A cache read block is required." unless block_given?
      @on_cache_read = block
    end

    def on_cache_write(&block)
      raise ArgumentError, "A cache write block is required." unless block_given?
      @on_cache_write = block
    end

    private

    def perform_query(query_str, operation_name, tracer, &block)
      digest = @digest_class.hexdigest([query_str, operation_name, VERSION].join(" "))
      if @lru && (hot_query = @lru.get(digest))
        return hot_query.perform(tracer, source_query: query_str, &block)
      end

      if @on_cache_read && (json = @on_cache_read.call(digest))
        prepared_query = PreparedQuery.new(JSON.parse(json))
        @lru.set(digest, prepared_query, json.bytesize) if @lru
        return prepared_query.perform(tracer, source_query: query_str, &block)
      end

      query = tracer.span("parse") do
        GraphQL::Query.new(schema, query: query_str, operation_name: operation_name)
      end
      errors = tracer.span("validate") do
        schema.static_validator.validate(query)[:errors]
      end
      raise ValidationError.new(errors: errors.map(&:to_h)) if errors.any?

      if introspection_query?(query)
        return PreparedQuery::Result.new(
          query: query_str,
          tracer: tracer,
          result: query.result.to_h,
        )
      end

      prepared_query = tracer.span("transform_request") do
        RequestTransformer.new(query).perform.to_prepared_query
      end
      json = prepared_query.to_json
      @on_cache_write.call(digest, json) if @on_cache_write
      @lru.set(digest, prepared_query, json.bytesize) if @lru
      prepared_query.perform(tracer, source_query: query_str, &block)
    end

    def introspection_query?(query)
      return false unless query.query?

      root_field_names = collect_root_field_names(query, query.selected_operation.selections)
      return false if root_field_names.none? { INTROSPECTION_FIELDS.include?(_1) }

      # hard limitation... data and introspections resolve from different places
      unless root_field_names.all? { INTROSPECTION_FIELDS.include?(_1) }
        raise ValidationError, "Custom data schemas cannot combine data fields with introspection fields."
      end

      true
    end

    def collect_root_field_names(query, selections, names = [])
      selections.each do |node|
        case node
        when GraphQL::Language::Nodes::Field
          names << node.name
        when GraphQL::Language::Nodes::InlineFragment
          collect_root_field_names(query, node.selections, names)
        when GraphQL::Language::Nodes::FragmentSpread
          collect_root_field_names(query, query.fragments[node.name].selections, names)
        end
      end
      names
    end

    def schema_file_name(handle, app_context_id = nil)
      file_name = "#{handle}_#{@admin.api_version}_cli#{@admin.api_client_id}"
      file_name << "_app#{app_context_id}" if app_context_id
      file_name << ".graphql"
      file_name
    end

    def with_file_store(file_name, force_reload: false, stringify: :to_definition)
      return yield if force_reload || @file_store_path.nil?

      file_path = @file_store_path.join(file_name).to_s
      File.read(file_path)
    rescue Errno::ENOENT
      result = yield
      File.write(file_path, result.public_send(stringify))
      result
    end
  end
end
