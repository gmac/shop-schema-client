# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)

require "bundler/setup"
Bundler.require(:default, :test)

require "minitest/pride"
require "minitest/autorun"
require "net/http"
require "uri"
require "json"

def load_base_admin_schema
  sdl = File.read("#{__dir__}/fixtures/admin_2025_01_public.graphql")
  schema = GraphQL::Schema.from_definition(sdl)
  schema.use(GraphQL::Schema::Visibility)
  schema
end

def load_shop_fixtures_catalog(app_id: nil)
  catalog = ShopifyCustomDataGraphQL::CustomDataCatalog.new(app_id: app_id)

  data = JSON.parse(File.read("#{__dir__}/fixtures/metafields.json"))
  data.each { catalog.add_metafield(_1) }

  data = JSON.parse(File.read("#{__dir__}/fixtures/metaobjects.json"))
  data.each { catalog.add_metaobject(_1) }

  catalog
end

def load_shop_fixtures_schema(app_id: nil)
  schema = ShopifyCustomDataGraphQL::SchemaComposer.new(
    load_base_admin_schema,
    load_shop_fixtures_catalog(app_id: app_id),
  ).perform

  # File.write("#{__dir__}/fixtures/admin_2025_01_#{app_id ? "app#{app_id}" : "shop"}.graphql", schema.to_definition)
  schema
end

$base_schema = nil
$app_schema = nil
$shop_schema = nil
$shop_api_client = nil
$metafield_values = nil

def base_schema
  $base_schema ||= load_base_admin_schema
end

def app_schema
  $app_schema ||= load_shop_fixtures_schema(app_id: 123)
end

def shop_schema
  $shop_schema ||= load_shop_fixtures_schema
end

def metafield_values
  $metafield_values ||= JSON.parse(File.read("#{__dir__}/fixtures/metafield_values.json"))
end

def shop_api_client
  $shop_api_client ||= begin
    secrets = JSON.parse(File.read("#{__dir__}/../secrets.json"))
    ShopifyCustomDataGraphQL::AdminApiClient.new(
      shop_url: secrets["shop_url"],
      access_token: secrets["access_token"],
    )
  end
end

def fetch_response(casette_name, query, version: "2025-01", variables: nil)
  file_path = "#{__dir__}/fixtures/responses/#{casette_name}.json"
  JSON.parse(File.read(file_path))
rescue Errno::ENOENT
  data = shop_api_client.fetch(query, variables: variables)
  data.delete("extensions")
  File.write(file_path, JSON.pretty_generate(data))
  data
end
