# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'bundler/setup'
Bundler.require(:default, :test)

require 'minitest/pride'
require 'minitest/autorun'
require 'net/http'
require 'uri'
require 'json'

def load_base_admin_schema
  sdl = File.read("#{__dir__}/fixtures/admin_2025_01_public.graphql")
  GraphQL::Schema.from_definition(sdl)
end

def load_fixture_catalog
  data = JSON.parse(File.read("#{__dir__}/fixtures/metaobjects.json"))
  metaobjects = data.map do |metaobject_def|
    ShopSchemaClient::SchemaComposer::MetaobjectDefinition.from_graphql(metaobject_def)
  end

  data = JSON.parse(File.read("#{__dir__}/fixtures/metafields.json"))
  metafields = data.map do |metafield_def|
    ShopSchemaClient::SchemaComposer::MetafieldDefinition.from_graphql(metafield_def)
  end

  catalog = ShopSchemaClient::SchemaComposer::MetaschemaCatalog.new
  catalog.add_metaobjects(metaobjects)
  catalog.add_metafields(metafields)
  catalog
end

def load_fixture_schema
  ShopSchemaClient::SchemaComposer.new(load_base_admin_schema, load_fixture_catalog).perform
end

$shop_schema = nil
$shop_secrets = nil

def shop_schema
  $shop_schema = load_fixture_schema if $shop_schema.nil?
  $shop_schema
end

def fetch_response(casette_name, query, version: "2025-01", variables: nil)
  file_path = "#{__dir__}/fixtures/casettes/#{casette_name}.json"
  JSON.parse(File.read(file_path))
rescue Errno::ENOENT
  $shop_secrets ||= JSON.parse(File.read("#{__dir__}/../secrets.json"))
  response = ::Net::HTTP.post(
    URI("#{$shop_secrets["shop_url"]}/admin/api/#{version}/graphql"),
    JSON.generate({
      "query" => query,
      "variables" => variables,
    }),
    {
      "X-Shopify-Access-Token" => $shop_secrets["access_token"],
      "Content-Type" => "application/json",
      "Accept" => "application/json",
    },
  )
  File.write(file_path, response.body)
  JSON.parse(response.body)
end
