# frozen_string_literal: true

module ShopifyCustomDataGraphQL
  class PreparedQuery
    DEFAULT_TRACER = Tracer.new

    class Result
      attr_reader :query, :tracer, :result

      def initialize(query:, tracer:, result:)
        @query = query
        @tracer = tracer
        @result = result
      end

      def to_h
        @result
      end
    end

    attr_reader :query, :transforms

    def initialize(params)
      @query = params["query"]
      @transforms = params["transforms"]

      unless @query && @transforms
        raise ArgumentError, "PreparedQuery requires params `query` and `transforms`"
      end
    end

    def as_json
      {
        "query" => @query,
        "transforms" => @transforms,
      }
    end

    def to_json
      as_json.to_json
    end

    def perform(tracer = DEFAULT_TRACER, source_query: nil)
      query = source_query && @transforms.none? ? source_query : @query
      raw_result = tracer.span("proxy") { yield(query) }

      result = if @transforms.any?
        tracer.span("transform_response") do
          ResponseTransformer.new(@transforms).perform(raw_result)
        end
      else
        raw_result
      end

      Result.new(query: query, tracer: tracer, result: result)
    end
  end
end
