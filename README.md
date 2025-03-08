# Shopify Custom Data GraphQL

A Shopify Admin API client for interacting with a Shop or App's metafields and metaobjects through a statically-typed GraphQL API, similar to [Contentful](https://www.contentful.com/developers/docs/references/graphql). This allows complex custom data queries such as this:

```graphql
query GetProduct($id: ID!) {
  product(id: $id) {
    id
    title
    rating: metafield(key: "custom.rating") { jsonValue }
    tacoPairing: metafield(key: "custom.taco_pairing") {
      reference {
        ... on Metaobject {
          name: field(key: "name") { jsonValue }
          protein: field(key: "protein") {
            reference {
              ... on Metaobject {
                name: field(key: "name") { jsonValue }
                calories: field(key: "calories") { jsonValue }
              }
            }
          }
        }
      }
    }
  }
}
```

To be expressed as this:

```graphql
query GetProduct($id: ID!) {
  product(id: $id) {
    id
    title
    extensions { # These are metafields...
      rating { # this is a metafield value!
        max
        value
      }
      tacoPairing { # this is a metaobject!
        name
        protein { # this is a metaobject!
          name
          calories
        }
      }
    }
  }
}
```

The client works by composing a superset of the Shopify Admin API schema with a Shop or App's custom data modeling inserted. All normal Admin API queries work with additional access to custom data extensions. This custom schema provides introspection (for live documentation), request validation, and transforms custom data queries into native Admin API requests.

With layers of caching, these custom data queries can be performed with very little overhead.

## Getting started

Add to your Gemfile:

```ruby
gem "shopify_custom_data_graphql"
```

Run bundle install, then require unless running an autoloading framework (Rails, etc):

```ruby
require "shopify_custom_data_graphql"
```

Setup a client:

```ruby
def launch
  # Build a client...
  @client = ShopifyCustomDataGraphQL::Client.new(
    shop_url: ENV["shop_url"], # << "https://myshop.myshopify.com"
    access_token: ENV["access_token"],
    api_version: "2025-01",
    file_store_path: Rails.root.join("db/schemas"),
  )

  # Add hooks for caching processed queries...
  @client.on_cache_read { |key| $mycache.get(key) }
  @client.on_cache_write { |key, value| $mycache.set(key, value) }

  # Eager-load schemas into the client...
  # (takes several seconds for the initial cold start, then gets faster)
  @client.eager_load!
end
```

Make requests:

```ruby
def graphql
  result = @client.execute(
    query: params["query"],
    variables: params["variables"],
    operation_name: params["operationName"],
  )
  JSON.generate(result)
end
```

## Configuration

A Client can be built with the following options:

* `shop_url`: the base url of the Shop to target, without any path information.
* `access_token`: an Admin API access token for the given Shop URL. The corresponding app must have at least read_metaobjects access.
* `api_version`: the Admin API version to target, ex: "2025-01". While there are no enforced limitations on schema version, in practice you should only target stable schemas with a full year of support. Avoid unstable and release candidate versions that may change.
* `file_store_path`: a repo location for writing schema files. While a first-time startup may take 10+ seconds to fetch all the necessary data, the generated schemas can be written to file and comitted to your repo for reuse. Subsequent startups reading from local schema files take less than a second. You can always delete the schema files in this store to have them regerated.
* `lru_max_bytesize`: the maximum bytesize for caching transformed requests, measured by their JSON bytesize. LRU requests perform no pre-processing and minimal post-processing of responses, so are extremely fast with generally only a fraction of a millisecond overhead.
* `app_context_id`: specifies an App ID to use as the base semantic context for custom data naming. See notes below.
* `base_namespaces`: an array of metafield namespaces to organize as base custom schema fields. While multiple metafield namespaces can be placed into the base scope, this runs the risk of naming collissions. See notes below.
* `scoped_namespaces`: an array of metafield namespaces to include in the schema with their namespace prefixes preserved.
