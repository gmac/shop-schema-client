# frozen_string_literal: true

require 'puma'
require 'rackup'
require 'json'
require 'graphql'
require 'rainbow'
require_relative '../lib/shopify_custom_data_graphql'

class App
  def initialize
    @graphiql = File.read("#{__dir__}/graphiql.html")

    secrets = begin
      JSON.parse(
        File.exist?("#{__dir__}/secrets.json") ?
        File.read("#{__dir__}/secrets.json") :
        File.read("#{__dir__}/../secrets.json")
      )
    rescue Errno::ENOENT
      raise "A `secrets.json` file is required, see `example/README.md`"
    end

    @mock_cache = {}
    @client = ShopifyCustomDataGraphQL::Client.new(
      shop_url: secrets["shop_url"],
      access_token: secrets["access_token"],
      api_version: "2025-01",
      file_store_path: "#{__dir__}/tmp",
    )

    @client.on_cache_read { |k| @mock_cache[k] }
    @client.on_cache_write { |k, v| @mock_cache[k] = v }

    puts Rainbow("Loading custom data schema...").cyan.bright
    @client.eager_load!
    puts Rainbow("Done.").cyan
  end

  def call(env)
    req = Rack::Request.new(env)
    case req.path_info
    when /graphql/
      timestamp = Time.current
      params = JSON.parse(req.body.read)
      result = @client.execute(
        query: params["query"],
        variables: params["variables"],
        operation_name: params["operationName"],
      )

      message = [Rainbow("[request #{timestamp.to_s}]").cyan.bright]
      stats = []
      if result.tracer["transform_request"]
        stats << "#{Rainbow("transform_request").magenta}: #{ms(result.tracer["transform_request"])}"
      end
      if result.tracer["transform_response"]
        stats << "#{Rainbow("transform_response").magenta}: #{ms(result.tracer["transform_response"])}"
      end
      if result.tracer["proxy"]
        stats << "#{Rainbow("proxy").magenta}: #{ms(result.tracer["proxy"])}"
      end
      message << stats.join(", ")
      message << "\n#{result.query}" if result.tracer["transform_request"]
      puts message.join(" ")

      [200, {"content-type" => "application/json"}, [JSON.generate(result.to_h)]]
    when /refresh/
      reload_shop_schema
      [200, {"content-type" => "text/html"}, ["Shop schema refreshed!"]]
    else
      [200, {"content-type" => "text/html"}, [@graphiql]]
    end
  end

  def ms(n)
    "#{(n * 100).round / 100.to_f}ms"
  end
end

Rackup::Handler.default.run(App.new, :Port => 3000)
