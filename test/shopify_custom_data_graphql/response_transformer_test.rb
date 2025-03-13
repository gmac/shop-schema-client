# frozen_string_literal: true

require "test_helper"

describe "ResponseTransformer" do
  PRODUCT_ID = "gid://shopify/Product/6885875646486"

  def test_transforms_extensions_scalar_fields
    result = fetch("transforms_extensions_scalar_fields", %|query {
      product(id: "#{PRODUCT_ID}") {
        id
        extensions {
          boolean
          color
        }
      }
    }|)

    expected = {
      "product" => {
        "id" => PRODUCT_ID,
        "extensions" => {
          "boolean" => true,
          "color" => "#006ba0",
        },
      },
    }

    assert_equal expected, result.dig("data")
  end

  def test_transforms_extensions_value_object_fields
    result = fetch("transforms_extensions_value_object_fields", %|query {
      product(id: "#{PRODUCT_ID}") {
        id
        extensions {
          dimension { unit value }
          rating { maximum: max value }
        }
      }
    }|)

    expected = {
      "product" => {
        "id" => PRODUCT_ID,
        "extensions" => {
          "dimension" => {
            "unit" => "INCHES",
            "value" => 24.0,
          },
          "rating" => {
            "maximum" => 5.0,
            "value" => 5.0,
          },
        },
      },
    }

    assert_equal expected, result.dig("data")
  end

  def test_transforms_extensions_reference_fields
    result = fetch("transforms_extensions_reference_fields", %|query {
      product(id: "#{PRODUCT_ID}") {
        id
        extensions {
          fileReference { id alt }
          productReference { id title }
        }
      }
    }|)

    expected = {
      "product" => {
        "id" => PRODUCT_ID,
        "extensions" => {
          "fileReference" => {
            "id" => "gid://shopify/MediaImage/20354823356438",
            "alt" => "",
          },
          "productReference" => {
            "id" => "gid://shopify/Product/6561850556438",
            "title" => "Aquanauts Crystal Explorer Sub",
          },
        },
      },
    }

    assert_equal expected, result.dig("data")
  end


  def test_transforms_extensions_reference_list_fields
    result = fetch("transforms_extensions_reference_list_fields", %|query {
      product(id: "#{PRODUCT_ID}") {
        id
        extensions {
          fileReferenceList(first: 10, after: "r2d2") {
            nodes { id alt }
          }
          productReferenceList(last: 10, before: "c3p0") {
            edges { node { id title } }
          }
        }
      }
    }|)

    expected = {
      "product" => {
        "id" => PRODUCT_ID,
        "extensions" => {
          "fileReferenceList" => {
            "nodes" => [{
              "id" => "gid://shopify/MediaImage/20354823356438",
              "alt" => "A scenic landscape",
            }],
          },
          "productReferenceList" => {
            "edges" => [{
              "node" => {
                "id" => "gid://shopify/Product/6561850556438",
                "title" => "Aquanauts Crystal Explorer Sub",
              },
            }],
          },
        },
      },
    }

    assert_equal expected, result.dig("data")
  end

  def test_transforms_extensions_typename
    result = fetch("transforms_extensions_typename", %|query {
      product(id: "#{PRODUCT_ID}") {
        __typename
        extensions { __typename }
      }
    }|)

    expected = {
      "product" => {
        "__typename" => "Product",
        "extensions" => { "__typename" => "ProductExtensions" },
      },
    }

    assert_equal expected, result.dig("data")
  end

  def test_transforms_nested_extension_fields
    result = fetch("transforms_nested_extension_fields", %|query {
      product(id: "#{PRODUCT_ID}") {
        title
        extensions {
          productReference {
            title
            extensions {
              boolean
              color
            }
          }
        }
      }
    }|)

    expected = {
      "product" => {
        "title" => "Neptune Discovery Base",
        "extensions" => {
          "productReference" => {
            "title" => "Crystal Explorer Sub",
            "extensions" => {
              "boolean" => true,
              "color" => "#0000FF",
            }
          }
        }
      }
    }

    assert_equal expected, result.dig("data")
  end

  def test_transforms_extension_fields_with_aliases
    result = fetch("transforms_extension_fields_with_aliases", %|query {
      product(id: "#{PRODUCT_ID}") {
        extensions1: extensions {
          myBoolean: boolean
          myTypename: __typename
        }
        extensions2: extensions {
          myColor: color
        }
      }
    }|)

    expected = {
      "product" => {
        "extensions1" => {
          "myBoolean" => true,
          "myTypename" => "ProductExtensions",
        },
        "extensions2" => {
          "myColor" => "#0000FF",
        },
      },
    }

    assert_equal expected, result.dig("data")
  end

  def test_transforms_metaobject_scalar_fields
    result = fetch("transforms_metaobject_scalar_fields", %|query {
      product(id: "#{PRODUCT_ID}") {
        extensions {
          widget {
            boolean
            color
          }
        }
      }
    }|)

    expected = {
      "product" => {
        "extensions" => {
          "widget" => {
            "boolean" => true,
            "color" => "#0000FF",
          },
        },
      },
    }

    assert_equal expected, result.dig("data")
  end

  def test_transforms_metaobject_value_object_fields
    result = fetch("transforms_metaobject_value_object_fields", %|query {
      product(id: "1") {
        extensions {
          widget {
            dimension { unit value }
            rating { maximum: max value }
          }
        }
      }
    }|)

    expected = {
      "product" => {
        "extensions" => {
          "widget" => {
            "dimension" => {
              "unit" => "INCHES",
              "value" => 23.0
            },
            "rating" => {
              "maximum" => 5.0,
              "value" => 5.0
            }
          }
        }
      }
    }

    assert_equal expected, result.dig("data")
  end

  def test_transforms_mixed_reference_with_matching_type_selection
    result = fetch("mixed_reference_returning_taco", %|query {
      product(id: "1") {
        extensions {
          mixedReference {
            ... on TacoMetaobject { id name }
            ... on TacoFillingMetaobject { id calories }
            __typename
          }
        }
      }
    }|)

    expected = {
      "product" => {
        "extensions" => {
          "mixedReference" => {
            "id" => "gid://shopify/Metaobject/1",
            "name" => "Al Pastor",
            "__typename" => "TacoMetaobject",
          },
        },
      },
    }

    assert_equal expected, result.dig("data")
  end

  def test_transforms_mixed_reference_without_matching_type_selection
    result = fetch("mixed_reference_returning_taco", %|query {
      product(id: "1") {
        extensions {
          mixedReference {
            ... on TacoFillingMetaobject { id calories }
            __typename
          }
        }
      }
    }|)

    expected = {
      "product" => {
        "extensions" => {
          "mixedReference" => {
            "__typename" => "TacoMetaobject",
          },
        },
      },
    }

    assert_equal expected, result.dig("data")
  end

  def test_transforms_errors_with_object_paths
    result = fetch("errors_with_object_path", %|query {
      product(id: "#{PRODUCT_ID}") {
        extensions {
          widget {
            system {
              createdByStaff { name }
            }
          }
        }
      }
    }|)

    expected_errors = [{
      "message" => "Access denied for createdByStaff field.",
      "path" => ["product", "extensions", "widget", "system", "createdByStaff"],
      "extensions" => { "code" => "ACCESS_DENIED" },
    }]

    assert_equal expected_errors, result.dig("errors")
  end

  def test_transforms_errors_with_list_paths
    result = fetch("errors_with_list_path", %|query {
      products(first: 1) {
        nodes {
          extensions {
            widget {
              system {
                createdByStaff { name }
              }
            }
          }
        }
      }
    }|)

    expected_errors = [{
      "message" => "Access denied for createdByStaff field.",
      "path" => ["products", "nodes", 0, "extensions", "widget", "system", "createdByStaff"],
      "extensions" => { "code" => "ACCESS_DENIED" },
    }]

    assert_equal expected_errors, result.dig("errors")
  end

  private

  def fetch(fixture, document, variables: {}, operation_name: nil, schema: nil)
    query = GraphQL::Query.new(
      schema || shop_schema,
      query: document,
      variables: variables,
      operation_name: operation_name,
    )

    errors = query.schema.static_validator.validate(query)[:errors]
    refute errors.any?, "Invalid custom data query: #{errors.first.message}" if errors.any?
    shop_query = ShopifyCustomDataGraphQL::RequestTransformer.new(query).perform.to_prepared_query
    shop_query.perform do |query_string|
      fetch_response(fixture, query_string)
    end
  end
end
