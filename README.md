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

Try the [example server](./example/README.md), and [learn how it works](./docs/methodology.md).

TL;DR – the client composes a superset of the Shopify Admin API schema with a Shop or App's custom data modeling inserted. All normal Admin API queries work with additional access to custom data extensions. This workflow provides introspection (for live documentation), request validation, and transforms custom data queries into native Admin API requests. With layers of caching, these custom data queries can be performed very efficiently with little overhead.

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
    shop_url: ENV["SHOP_URL"],
    access_token: ENV["ACCESS_TOKEN"],
    api_version: "2025-01",
    file_store_path: Rails.root.join("db/schemas"),
    lru_max_bytesize: 10.megabytes,
  )

  # Add hooks for caching processed queries (optional; use memcached, redis, etc)...
  @client.on_cache_read { |key| $mycache.get(key) }
  @client.on_cache_write { |key, value| $mycache.set(key, value) }

  # Eager-load schemas into the client...
  # (takes several seconds on first-time launch, then gets faster)
  @client.eager_load!
end
```

Make requests:

```ruby
def custom_data_graphql
  result = @client.execute(
    query: params["query"],
    variables: params["variables"],
    operation_name: params["operationName"],
  )
  JSON.generate(result)
end
```

## Configuration

A `ShopifyCustomDataGraphQL::Client` takes the following options:

* **`shop_url`**: _required_, base url of the Shop to target; ex: `https://myshop.myshopify.com`.
* **`access_token`**: _required_, an Admin API access token for the given shop. The corresponding app must have `read_metaobject_definitions` access and permissions for all desired metafield resource types.
* **`api_version`**: _required_, the Admin API version to target, ex: `2025-01`. While there are no hard version requirements, in practice you should only target stable versions. Avoid `unstable` and release candidate versions that may change.
* **`app_context_id`**: specifies an app ID that provides the schema's base fields and types. See [how namespaces work](#custom-data-namespaces) below.
* **`base_namespaces`**: an array of metafield namespaces to use as the schema's base fields. Note that putting multiple namespaces into the base scope together runs the risk of name collisions. See [how namespaces work](#custom-data-namespaces) below.
* **`prefixed_namespaces`**: an array of metafield namespaces to include with their namespace preserved as a prefix. See [how namespaces work](#custom-data-namespaces) below.
* **`file_store_path`**: a repo location for writing generated schema files. While a first-time launch may take 10+ seconds to fetch all necessary data, the resulting schemas can be written as repo files and committed for reuse. Subsequent startups using local schema files should take less than a second.
* **`lru_max_bytesize`**: the maximum bytesize for caching transformed requests in memory, measured by their JSON bytesize. LRU requests perform no pre-processing and hit no external caches, so are _extremely_ fast with generally only nanoseconds of overhead necessary for shaping responses.
* **`digest_class`**: a preferred `Digest` class that statically implements `hexdigest`. Uses `Digest::MD5` by default.

## Custom data namespaces

Shopify custom data uses namespacing to scope metafields and metaobjects by their ownership. A `Client` lets you select how various namespaces are incorporated into the custom data schema, which can provide a shop-centric or app-centric focus in the schema modeling.

### Shop schemas

A Shop schema will generally promote a shop's `custom` metafields namespace (the default namespace used by the Shopify admin) as base schema fields. Additional namespaces can be included with prefixing:

```ruby
client = ShopifyCustomDataGraphQL::Client.new(
  # ...
  base_namespaces: ["custom"],
  prefixed_namespaces: ["other", "app--*"],
  app_context_id: nil,
)
```

This will translate metafields/metaobjects into schema elements as follows:

* **`custom.my_field`** → `myField`
* **`other.my_field`** → `other_myField`
* **`app--123.my_field`**: → `app123_myField`
* **`app--123--other.my_field`** → `app123_other_myField`
* **`my_type`** → `MyTypeMetaobject`
* **`app--123--my_type`** → `MyTypeApp123Metaobject`

### App schemas

An App schema promotes an app-owned custom data namespace as base fields and type names. For example:

```ruby
client = ShopifyCustomDataGraphQL::Client.new(
  # ...
  base_namespaces: ["$app"],
  prefixed_namespaces: ["$app:*", "app--*", "custom"],
  app_context_id: 123,
)
```

Results in:

* **`custom.my_field`** → `custom_myField`
* **`app--123.my_field`**: → `myField`
* **`app--123--other.my_field`** → `other_myField`
* **`app--456.my_field`** → `app456_myField`
* **`my_type`** → `MyTypeShopMetaobject`
* **`app--123--my_type`** → `MyTypeMetaobject`
* **`app--456--my_type`** → `MyTypeApp456Metaobject`

Providing just `app_context_id` will automatically filter the schema down to just `$app` fields and types owned by the specified app id.

### Combined namespaces

A schema _may_ promote multiple namespaces as base fields and type names. However, this can result in name collisions, and so should only be done for shop-specific apps where all namespace combinatorials are known:

```ruby
client = ShopifyCustomDataGraphQL::Client.new(
  # ...
  base_namespaces: ["$app", "custom"],
  prefixed_namespaces: ["*"],
  app_context_id: 123,
)
```

## Tests

```shell
bundle install
bundle exec rake test [TEST=path/to/test.rb]
```
