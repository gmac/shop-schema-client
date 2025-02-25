# frozen_string_literal: true

require "test_helper"

describe "RequestTransformer" do
  def test_transforms_extensions_scalar_fields
    result = transform_request(%|query {
      product(id: "1") {
        title
        extensions {
          boolean
          color
        }
      }
    }|)

    expected_query = %|query {
      product(id: "1") {
        title
        ___extensions_boolean: metafield(key: "custom.boolean") { value }
        ___extensions_color: metafield(key: "custom.color") { value }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "boolean" => { "fx" => { "t" => "boolean" } },
            "color" => { "fx" => { "t" => "color" } },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_transforms_extensions_value_object_fields
    result = transform_request(%|query {
      product(id: "1") {
        title
        extensions {
          dimension { unit value }
          rating { maximum: max value }
        }
      }
    }|)

    expected_query = %|query {
      product(id: "1") {
        title
        ___extensions_dimension: metafield(key: "custom.dimension") { value }
        ___extensions_rating: metafield(key: "custom.rating") { value }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "dimension" => { "fx" => { "t" => "dimension", "s" => ["unit", "value"] } },
            "rating" => { "fx" => { "t" => "rating", "s" => ["maximum:max", "value"] } },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_transforms_extensions_reference_fields
    result = transform_request(%|query {
      product(id: "1") {
        title
        extensions {
          fileReference { id alt }
          productReference { id title }
        }
      }
    }|)

    expected_query = %|query {
      product(id: "1") {
        title
        ___extensions_fileReference: metafield(key: "custom.file_reference") {
          reference { ... on File { id alt } }
        }
        ___extensions_productReference: metafield(key: "custom.product_reference") {
          reference { ... on Product { id title } }
        }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "fileReference" => { "fx" => { "t" => "file_reference" } },
            "productReference" => { "fx" => { "t" => "product_reference" } },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_transforms_extensions_reference_list_fields
    result = transform_request(%|query {
      product(id: "1") {
        title
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

    expected_query = %|query {
      product(id: "1") {
        title
        ___extensions_fileReferenceList: metafield(key: "custom.file_reference_list") {
          references(first: 10, after: "r2d2") {
            nodes { ... on File { id alt } }
          }
        }
        ___extensions_productReferenceList: metafield(key: "custom.product_reference_list") {
          references(last: 10, before: "c3p0") {
            edges { node { ... on Product { id title } } }
          }
        }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "fileReferenceList" => { "fx" => { "t" => "list.file_reference" } },
            "productReferenceList" => { "fx" => { "t" => "list.product_reference" } },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_transforms_extensions_typename
    result = transform_request(%|query {
      product(id: "1") {
        __typename
        extensions { __typename }
      }
    }|)

    expected_query = %|query {
      product(id: "1") {
        __typename
        ___extensions___typename: __typename
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "__typename" => { "fx" => { "t" => "extensions_typename" } },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_transforms_nested_extension_fields
    result = transform_request(%|query {
      product(id: "1") {
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

    expected_query = %|query {
      product(id: "1") {
        title
        ___extensions_productReference: metafield(key: "custom.product_reference") {
          reference {
            ... on Product {
              title
              ___extensions_boolean: metafield(key: "custom.boolean") { value }
              ___extensions_color: metafield(key: "custom.color") { value }
            }
          }
        }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "productReference" => {
              "fx" => { "t" => "product_reference" },
              "f" => {
                "extensions" => {
                  "fx" => { "t" => "metafield_extensions" },
                  "f" => {
                    "boolean" => { "fx" => { "t" => "boolean" } },
                    "color" => { "fx" => { "t" => "color" } },
                  },
                },
              },
            },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_transforms_extension_fields_with_aliases
    result = transform_request(%|query {
      product(id: "1") {
        title
        extensions1: extensions {
          myBoolean: boolean
          myTypename: __typename
        }
        extensions2: extensions {
          myColor: color
        }
      }
    }|)

    expected_query = %|query {
      product(id: "1") {
        title
        ___extensions1_myBoolean: metafield(key: "custom.boolean") { value }
        ___extensions1_myTypename: __typename
        ___extensions2_myColor: metafield(key: "custom.color") { value }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions1" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "myBoolean" => { "fx" => { "t" => "boolean" } },
            "myTypename" => { "fx" => { "t" => "extensions_typename" } },
          },
        },
        "extensions2" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "myColor" => { "fx" => { "t" => "color" } },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_restricts_reserved_alias_prefix
    error = assert_raises(ShopSchemaClient::ValidationError) do
      transform_request(%|query {
        product(id: "1") { ___sfoo: title }
      }|)
    end

    assert_equal "Field aliases starting with `___` are reserved for system use.", error.message
  end

  def test_transforms_metaobject_scalar_fields
    result = transform_request(%|query {
      product(id: "1") {
        extensions {
          widget {
            boolean
            color
          }
        }
      }
    }|)

    expected_query = %|query {
      product(id: "1") {
        ___extensions_widget: metafield(key: "custom.widget") {
          reference {
            ... on Metaobject {
              boolean: field(key: "boolean") { value }
              color: field(key: "color") { value }
            }
          }
        }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "widget" => {
              "fx" => { "t" => "metaobject_reference" },
              "f" => {
                "boolean" => { "fx" => { "t" => "boolean" } },
                "color" => { "fx" => { "t" => "color" } },
              },
            },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_transforms_metaobject_value_object_fields
    result = transform_request(%|query {
      product(id: "1") {
        extensions {
          widget {
            dimension { unit value }
            rating { maximum: max value }
          }
        }
      }
    }|)

    expected_query = %|query {
      product(id: "1") {
        ___extensions_widget: metafield(key: "custom.widget") {
          reference {
            ... on Metaobject {
              dimension: field(key: "dimension") { value }
              rating: field(key: "rating") { value }
            }
          }
        }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "widget" => {
              "fx" => { "t" => "metaobject_reference" },
              "f" => {
                "dimension" => { "fx" => { "t" => "dimension", "s" => ["unit", "value"] } },
                "rating" => { "fx" => { "t" => "rating", "s" => ["maximum:max", "value"] } },
              },
            },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_transforms_metaobject_reference_fields
    result = transform_request(%|query {
      product(id: "1") {
        extensions {
          widget {
            fileReference { id alt }
            productReference { id title }
          }
        }
      }
    }|)

    expected_query = %|query {
      product(id: "1") {
        ___extensions_widget: metafield(key: "custom.widget") {
          reference {
            ... on Metaobject {
              fileReference: field(key: "file_reference") {
                reference { ... on File { id alt } }
              }
              productReference: field(key: "product_reference") {
                reference { ... on Product { id title } }
              }
            }
          }
        }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "widget" => {
              "fx" => { "t" => "metaobject_reference" },
              "f" => {
                "fileReference" => { "fx" => { "t" => "file_reference" } },
                "productReference" => { "fx" => { "t" => "product_reference" } },
              },
            },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_transforms_metaobject_reference_list_fields
    result = transform_request(%|query {
      product(id: "1") {
        extensions {
          widget {
            fileReferenceList(first: 10, after: "r2d2") {
              nodes { id alt }
            }
            productReferenceList(last: 10, before: "c3p0") {
              edges { node { id title } }
            }
          }
        }
      }
    }|)

    expected_query = %|query {
      product(id: "1") {
        ___extensions_widget: metafield(key: "custom.widget") {
          reference {
            ... on Metaobject {
              fileReferenceList: field(key: "file_reference_list") {
                references(first: 10, after: "r2d2") {
                  nodes { ... on File { id alt } }
                }
              }
              productReferenceList: field(key: "product_reference_list") {
                references(last: 10, before: "c3p0") {
                  edges { node { ... on Product { id title } } }
                }
              }
            }
          }
        }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "widget" => {
              "fx" => { "t" => "metaobject_reference" },
              "f" => {
                "fileReferenceList" => { "fx" => { "t" => "list.file_reference" } },
                "productReferenceList" => { "fx" => { "t" => "list.product_reference" } },
              },
            },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_transforms_metaobject_typename
    result = transform_request(%|query {
      product(id: "1") {
        extensions {
          widget { __typename }
        }
      }
    }|)

    expected_query = %|query {
      product(id: "1") {
        ___extensions_widget: metafield(key: "custom.widget") {
          reference { ... on Metaobject { __typename: type } }
        }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "widget" => {
              "fx" => { "t" => "metaobject_reference" },
              "f" => {
                "__typename" => { "fx" => { "t" => "metaobject_typename" } },
              },
            },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_transforms_nested_metaobject_fields
    result = transform_request(%|query {
      product(id: "1") {
        extensions {
          widget {
            widget {
              boolean
              color
            }
          }
        }
      }
    }|)

    expected_query = %|query {
      product(id: "1") {
        ___extensions_widget: metafield(key: "custom.widget") {
          reference {
            ... on Metaobject {
              widget: field(key: "widget") {
                reference {
                  ... on Metaobject {
                    boolean: field(key: "boolean") { value }
                    color: field(key: "color") { value }
                  }
                }
              }
            }
          }
        }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "widget" => {
              "fx" => { "t" => "metaobject_reference" },
              "f" => {
                "widget" => {
                  "fx" => { "t" => "metaobject_reference" },
                  "f" => {
                    "boolean" => { "fx" => { "t" => "boolean" } },
                    "color" => { "fx" => { "t" => "color" } },
                  },
                },
              },
            },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_transforms_metaobject_fields_with_aliases
    result = transform_request(%|query {
      product(id: "1") {
        extensions {
          widget {
            myBoolean: boolean
            myColor: color
            myTypename: __typename
          }
        }
      }
    }|)

    expected_query = %|query {
      product(id: "1") {
        ___extensions_widget: metafield(key: "custom.widget") {
          reference {
            ... on Metaobject {
              myBoolean: field(key: "boolean") { value }
              myColor: field(key: "color") { value }
              myTypename: type
            }
          }
        }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "widget" => {
              "fx" => { "t" => "metaobject_reference" },
              "f" => {
                "myBoolean" => { "fx" => { "t" => "boolean" } },
                "myColor" => { "fx" => { "t" => "color" } },
                "myTypename" => { "fx" => { "t" => "metaobject_typename" } },
              },
            },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_only_transforms_custom_metaobject_fields
    result = transform_request(%|query {
      product(id: "1") {
        extensions {
          widget {
            id
            handle
            boolean
          }
        }
      }
    }|)

    expected_query = %|query {
      product(id: "1") {
        ___extensions_widget: metafield(key: "custom.widget") {
          reference {
            ... on Metaobject {
              id
              handle
              boolean: field(key: "boolean") { value }
            }
          }
        }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "widget" => {
              "fx" => { "t" => "metaobject_reference" },
              "f" => {
                "boolean" => { "fx" => { "t" => "boolean" } },
              },
            },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_coalesces_value_object_selections
    result = transform_request(%|query {
      product(id: "1") {
        extensions {
          rating {
            max
          }
          rating {
            min
            value
          }
        }
      }
    }|)

    expected_query = %|query {
      product(id: "1") {
        ___extensions_rating: metafield(key: "custom.rating") { value }
        ___extensions_rating: metafield(key: "custom.rating") { value }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "rating" => { "fx" => { "t" => "rating", "s" => ["max", "min", "value"] } },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_extracts_value_object_selection_fragents
    result = transform_request(%|query {
      product(id: "1") {
        extensions {
          rating1: rating {
            ... on RatingMetatype { max }
            ... RatingAttrs
            ... { value }
          }
          rating2: rating {
            ... {
              max
              ... on RatingMetatype {
                ... RatingAttrs
                value
              }
            }
          }
        }
      }
    }
    fragment RatingAttrs on RatingMetatype { min }
    |)

    expected_query = %|query {
      product(id: "1") {
        ___extensions_rating1: metafield(key: "custom.rating") { value }
        ___extensions_rating2: metafield(key: "custom.rating") { value }
      }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "rating1" => { "fx" => { "t" => "rating", "s" => ["max", "min", "value"] } },
            "rating2" => { "fx" => { "t" => "rating", "s" => ["max", "min", "value"] } },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_transforms_fragments_on_extensions_scope
    result = transform_request(%|query {
      product(id: "1") {
        extensions {
          ... on ProductExtensions { boolean }
          ...ProductExtensionsAttrs
        }
      }
    }
    fragment ProductExtensionsAttrs on ProductExtensions { color }
    |)

    expected_query = %|query {
      product(id: "1") {
        ___extensions_boolean: metafield(key: "custom.boolean") { value }
        ...ProductExtensionsAttrs
      }
    }
    fragment ProductExtensionsAttrs on Product {
      ___extensions_color: metafield(key: "custom.color") { value }
    }|

    expected_transforms = {
      "f" => {
        "extensions" => {
          "fx" => { "t" => "metafield_extensions" },
          "f" => {
            "boolean" => { "fx" => { "t" => "boolean" } },
            "color" => { "fx" => { "t" => "color" } },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f", "product")
  end

  def test_transforms_inline_fragments_with_type_condition
    result = transform_request(%|query {
      node(id: "1") {
        ... { id }
        ... on Product {
          title
          productExt: extensions { boolean }
        }
        ... on ProductVariant {
          title
          variantExt: extensions { test }
        }
      }
    }|)

    expected_query = %|query {
      node(id: "1") {
        ... on Node { id }
        ... on Product {
          title
          ___productExt_boolean: metafield(key: "custom.boolean") { value }
        }
        ... on ProductVariant {
          title
          ___variantExt_test: metafield(key: "custom.test") { value }
        }
        ___typehint: __typename
      }
    }|

    expected_transforms = {
      "node" => {
        "if" => {
          "Product" => {
            "f" => {
              "productExt" => {
                "fx" => { "t" => "metafield_extensions" },
                "f" => {
                  "boolean" => { "fx" => { "t" => "boolean" } },
                },
              },
            },
          },
          "ProductVariant" => {
            "f" => {
              "variantExt" => {
                "fx" => { "t" => "metafield_extensions" },
                "f" => {
                  "test" => { "fx" => { "t" => "boolean" } },
                },
              },
            },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f")
  end

  def test_transforms_fragment_spreads_with_type_condition
    result = transform_request(%|query {
      node(id: "1") {
        id
        ...ProductAttrs
        ...VariantAttrs
      }
    }
    fragment ProductAttrs on Product {
      title
      productExt: extensions { boolean }
    }
    fragment VariantAttrs on ProductVariant {
      title
      variantExt: extensions { test }
    }|)

    expected_query = %|query {
      node(id: "1") {
        id
        ...ProductAttrs
        ...VariantAttrs
        ___typehint: __typename
      }
    }
    fragment ProductAttrs on Product {
      title
      ___productExt_boolean: metafield(key: "custom.boolean") { value }
    }
    fragment VariantAttrs on ProductVariant {
      title
      ___variantExt_test: metafield(key: "custom.test") { value }
    }|

    expected_transforms = {
      "node" => {
        "if" => {
          "Product" => {
            "f" => {
              "productExt" => {
                "fx" => { "t" => "metafield_extensions" },
                "f" => {
                  "boolean" => { "fx" => { "t" => "boolean" } },
                },
              },
            },
          },
          "ProductVariant" => {
            "f" => {
              "variantExt" => {
                "fx" => { "t" => "metafield_extensions" },
                "f" => {
                  "test" => { "fx" => { "t" => "boolean" } },
                },
              },
            },
          },
        },
      },
    }

    assert_equal expected_query.squish, result.as_json["query"].squish
    assert_equal expected_transforms, result.as_json["transforms"].dig("f")
  end

  private

  def transform_request(document, variables: {}, operation_name: nil, schema: nil)
    query = GraphQL::Query.new(
      schema || shop_schema,
      query: document,
      variables: variables,
      operation_name: operation_name,
    )

    errors = query.schema.static_validator.validate(query)[:errors]
    refute errors.any?, errors.first.message if errors.any?
    ShopSchemaClient::RequestTransformer.new(query).perform
  end
end
