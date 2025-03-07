# shop-schema-client

An experimental client for interfacing with Shopify metafields and metaobjects through a statically-typed reference schema. Try out a working shop schema server in the [example](./example/README.md) folder. This system runs as a client, so could work directly in a web browser if ported to JavaScript.

This is still an early prototype.

## How it works

### 1. Compose a reference schema

A reference schema never _executes_ a request, it simply provides introspection and validation capabilities. This schema is built by loading all metafield and metaobject definitions from the Admin API (see [sample query](./example/server.rb)), then inserting those metaobjects and metafields as native types and fields into a base version of the Shopify Admin API (see [`SchemaComposer`](./lib/schema_composer.rb)). This creates static definitions for custom elements with naming carefully scoped to avoid conflicts with the base Admin schema, for example:

```graphql
type Product {
  # full native product fields...

  extensions: ProductExtensions!
}

type ProductExtensions {
  tacoPairing: TacoMetaobject @metafield(key: "taco_pairing", type: "metaobject_reference")
}

type TacoMetaobject {
  id: ID!

  name: String @metafield(key: "name", type: "single_line_text_field")

  protein: TacoFillingMetaobject @metafield(key: "protein", type: "metaobject_reference")

  rating: RatingMetatype @metafield(key: "rating", type: "rating")

  toppings(after: String, before: String, first: Int, last: Int): TacoFillingMetaobjectConnection @metafield(key: "toppings", type: "list.metaobject_reference")
}
```

Now we now have a Shop reference schema that can introspect and validate GraphQL queries structured like this:

```graphql
query GetProduct($id: ID!){
  product(id: $id) {
    id
    title
    extensions {
      # These are all metafields...!!
      similarProduct { # product_reference
        id
        title
      }
      myTaco: tacoPairing { # metaobject_reference
        # This is a metaobject...!!
        name
        rating { # rating
          max
          value
          __typename
        }
        protein { # metaobject_reference
          name
          volume { # volume
            value
            unit
          }
        }
        toppings(first: 10) { # list.metaobject_reference
          nodes {
            name
            calories # number_integer
          }
        }
      }
    }
  }
}
```

### 2. Transform requests

In order to send the above query to the Shopify Admin API, we need to transform it into a native query structure. The [`RequestTransfomer`](./lib/request_transformer.rb) automates this:

```graphql
query GetProduct($id: ID!) {
  product(id: $id) {
    id
    title
    ___extensions_similarProduct: metafield(key: "custom.similar_product") {
      reference {
        ... on Product {
          id
          title
        }
      }
    }
    ___extensions_myTaco: metafield(key: "custom.taco_pairing") {
      reference {
        ... on Metaobject {
          name: field(key: "name") { jsonValue }
          rating: field(key: "rating") { jsonValue }
          protein: field(key: "protein") {
            reference {
              ... on Metaobject {
                name: field(key: "name") { jsonValue }
                volume: field(key: "volume") { jsonValue }
              }
            }
          }
          toppings: field(key: "toppings") {
            references(first: 10) {
              nodes {
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
}
```

While transforming the request shape, a small JSON mapping is also generated to describe transformations needed in the response data:

```json
{
  "f": {
    "product": {
      "f": {
        "extensions": {
          "fx": { "t": "custom_scope" },
          "f": {
            "similarProduct": {
              "fx": { "t": "product_reference" }
            },
            "myTaco": {
              "fx": { "t": "metaobject_reference" },
              "f": {
                "name": {
                  "fx": { "t": "single_line_text_field" }
                },
                "rating": {
                  "fx": { "t": "rating", "s": ["max", "value", "__typename"] }
                },
                "protein": {
                  "fx": { "t": "metaobject_reference" },
                  "f": {
                    "name": {
                      "fx": { "t": "single_line_text_field" }
                    },
                    "volume": {
                      "fx": { "t": "volume", "s": ["unit", "value"] }
                    }
                  }
                },
                "toppings": {
                  "fx": { "t": "list.metaobject_reference" },
                  "f": {
                    "name": {
                      "fx": { "t": "single_line_text_field" }
                    },
                    "calories": {
                      "fx": { "t": "number_integer" }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```

With these transformation artifacts, a query can be computed once during development, cached, and used repeatedly in production without further dependence on the shop reference schema.

### 3. Transform responses

Lastly, the [`ResponseTransfomer`](./lib/response_transformer.rb) must run on all responses, and uses the transformation mapping to shape results to match the original request. This is a quick in-memory pass that adds modest transformation overhead to cached requests:

```json
{
  "product": {
    "id": "gid://shopify/Product/6885875646486",
    "title": "Neptune Discovery Lab",
    "extensions": {
      "similarProduct": {
        "id": "gid://shopify/Product/6561850556438",
        "title": "Aquanauts Crystal Explorer Sub"
      },
      "myTaco": {
        "name": "Al Pastor",
        "rating": {
          "min": 0,
          "value": 1,
          "__typename": "RatingMetatype"
        },
        "protein": {
          "name": "Pineapple",
          "volume": {
            "value": 2,
            "unit": "OUNCES"
          }
        },
        "toppings": {
          "nodes": [
            {
              "name": "Pineapple",
              "calories": 25
            }
          ]
        }
      }
    }
  }
}
```

## First principles

- Composing a shop reference schema or parsing a cached reference schema is slow (100ms+). These cold-starts should only be done in development.

- Transforming requests requires a shop reference schema, so are subject to cold-starts and should only happen in development. Transformed requests should be cached for production use.

- Transforming responses does NOT require a shop reference schema (a pre-computed transform map is used instead). This allows cached queries to transform their responses with minimal overhead in production.

## Usage

#### Composing a shop schema

See [server example](./example/server.rb). Composition would ideally be done by a Shopify backend, and simply send a shop's reference schema to a client as GraphQL SDL (schema definition language) for it to parse.

#### Making development requests

See [server example](./example/server.rb).

#### Making production requests

While in development mode, generate a shop query and save it as JSON:

```ruby
query = GraphQL::Query.new(query: "query Fancy($id:ID!){ product(id:$id) { extensions { ... } } }")
shop_query = ShopSchemaClient::RequestTransformer.new(query).perform
File.write("my_saved_query.json", shop_query.to_json)
```

This will save the transformed query and its response transform mapping as a JSON structure:

```json
{"query":"query {\n  product(id: \"gid://shopify/Product/6885875646486\") {\n    id\n    title\n    __ex_flexRating: metafield(key: \"custom.flex_rating\") {\n      value\n    }\n  }\n}","transforms":{"f":{"product":{"f":{"extensions":{"f":{"flexRating":{"fx":{"do":"mf_val","t":"number_decimal"}}}}},"ex":"extensions"}}}}
```

In production, load the saved query into a new `PreparedQuery`:

```ruby
json = File.read("my_saved_query.json")
shop_query = PreparedQuery.new(json)

response = shop_query.perform do |query_string|
  variables = { id: "gid://shopify/Product/1" }
  do_stuff_to_send_my_request(query_string, variables)
end
```

This saved query can be used repeatedly with zero pre-processing overhead, and minimal post-processing.
