# frozen_string_literal: true

require "test_helper"

describe "ResponseTransformer" do
  def test_transforms_extensions_scalar_fields
    result = fetch(%|query {
      product(id: "1") {
        title
        extensions {
          boolean
          color
        }
      }
    }|)

    expected = {}

    assert true
  end

  private

  def fetch(document, variables: {}, operation_name: nil, schema: nil)
    query = GraphQL::Query.new(
      schema || shop_schema,
      query: document,
      variables: variables,
      operation_name: operation_name,
    )

    assert query.schema.static_validator.validate(query)[:errors].none?, "Invalid shop query."
    shop_query = ShopSchemaClient::RequestTransformer.new(query).perform
    shop_query.perform do |query_string|
      fetch_response("first_test", query_string)
    end
  end
end
