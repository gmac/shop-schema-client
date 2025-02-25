# frozen_string_literal: true

require "test_helper"

describe "SchemaComposer" do
  def test_builds_color_metafield_type
    type = shop_schema.get_type("ColorMetatype")
    assert type.kind.scalar?
  end

  def test_builds_dimension_metafield_type
    type = shop_schema.get_type("DimensionMetatype")
    assert type.kind.object?
    assert_equal "String", type.get_field("unit").type.to_type_signature
    assert_equal "Float", type.get_field("value").type.to_type_signature
  end

  def test_builds_rating_metafield_type
    type = shop_schema.get_type("RatingMetatype")
    assert type.kind.object?
    assert_equal "Float", type.get_field("max").type.to_type_signature
    assert_equal "Float", type.get_field("max").type.to_type_signature
    assert_equal "Float", type.get_field("value").type.to_type_signature
  end

  def test_builds_rich_text_metafield_type
    type = shop_schema.get_type("RichTextMetatype")
    assert type.kind.scalar?
  end

  def test_builds_volume_metafield_type
    type = shop_schema.get_type("VolumeMetatype")
    assert type.kind.object?
    assert_equal "String", type.get_field("unit").type.to_type_signature
    assert_equal "Float", type.get_field("value").type.to_type_signature
  end

  def test_builds_metaobject_types
    type = shop_schema.get_type("TacoMetaobject")
    assert_equal "ID!", type.get_field("id").type.to_type_signature
    assert_equal "String!", type.get_field("handle").type.to_type_signature
    assert_equal "String", type.get_field("name").type.to_type_signature
    assert_equal "RatingMetatype", type.get_field("rating").type.to_type_signature
    assert_equal "TacoFillingMetaobject", type.get_field("protein").type.to_type_signature
    assert_equal "TacoFillingMetaobjectConnection", type.get_field("toppings").type.to_type_signature
  end

  def test_builds_metaobject_connection_types
    type = shop_schema.get_type("TacoMetaobjectConnection")
    edge_type = shop_schema.get_type("TacoMetaobjectEdge")
    assert_equal "[TacoMetaobject!]!", type.get_field("nodes").type.to_type_signature
    assert_equal "[TacoMetaobjectEdge!]!", type.get_field("edges").type.to_type_signature
    assert_equal "TacoMetaobject", edge_type.get_field("node").type.to_type_signature # << is this right?
  end

  def test_builds_native_type_extensions_scope
    extensions_field = shop_schema.get_type("Product").get_field("extensions")
    assert_equal "ProductExtensions!", extensions_field.type.to_type_signature
  end

  def test_builds_native_type_extensions_scope_for_all_owner_types
    shop_schema.possible_types(shop_schema.get_type("HasMetafields")).each do |owner_type|
      extensions_field = owner_type.get_field("extensions")
      assert extensions_field, "Expected extensions scope for type `#{owner_type.graphql_name}`."
      assert_equal "#{owner_type.graphql_name}Extensions!", extensions_field.type.to_type_signature
    end
  end

  def test_builds_connection_fields
    field = shop_schema.get_type("ProductExtensions").get_field("metaobjectReferenceList")
    assert_equal "Int", field.get_argument("first").type.to_type_signature
    assert_equal "Int", field.get_argument("last").type.to_type_signature
    assert_equal "String", field.get_argument("before").type.to_type_signature
    assert_equal "String", field.get_argument("after").type.to_type_signature
  end

  def test_builds_metafield_key_field_annotations
    directive = shop_schema
      .get_type("ProductExtensions")
      .get_field("dateTime")
      .directives
      .find { _1.graphql_name == "metafield" }
    assert_equal "date_time", directive.arguments.keyword_arguments[:key]
  end

  def test_builds_boolean_field
    field = shop_schema.get_type("ProductExtensions").get_field("boolean")
    assert_equal "Boolean", field.type.to_type_signature
    assert_equal "boolean", metafield_directive_type_for(field)
  end

  def test_builds_color_field
    field = shop_schema.get_type("ProductExtensions").get_field("color")
    assert_equal "ColorMetatype", field.type.to_type_signature
    assert_equal "color", metafield_directive_type_for(field)
  end

  def test_builds_color_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("colorList")
    assert_equal "[ColorMetatype]", field.type.to_type_signature
    assert_equal "list.color", metafield_directive_type_for(field)
  end

  def test_builds_collection_reference_field
    field = shop_schema.get_type("ProductExtensions").get_field("collectionReference")
    assert_equal "Collection", field.type.to_type_signature
    assert_equal "collection_reference", metafield_directive_type_for(field)
  end

  def test_builds_collection_reference_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("collectionReferenceList")
    assert_equal "CollectionConnection", field.type.to_type_signature
    assert_equal "list.collection_reference", metafield_directive_type_for(field)
  end

  def test_builds_company_reference_field
    field = shop_schema.get_type("ProductExtensions").get_field("companyReference")
    assert_equal "Company", field.type.to_type_signature
    assert_equal "company_reference", metafield_directive_type_for(field)
  end

  def test_builds_company_reference_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("companyReferenceList")
    assert_equal "CompanyConnection", field.type.to_type_signature
    assert_equal "list.company_reference", metafield_directive_type_for(field)
  end

  def test_builds_customer_reference_field
    field = shop_schema.get_type("ProductExtensions").get_field("customerReference")
    assert_equal "Customer", field.type.to_type_signature
    assert_equal "customer_reference", metafield_directive_type_for(field)
  end

  def test_builds_customer_reference_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("customerReferenceList")
    assert_equal "CustomerConnection", field.type.to_type_signature
    assert_equal "list.customer_reference", metafield_directive_type_for(field)
  end

  def test_builds_date_field
    field = shop_schema.get_type("ProductExtensions").get_field("date")
    assert_equal "Date", field.type.to_type_signature
    assert_equal "date", metafield_directive_type_for(field)
  end

  def test_builds_date_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("dateList")
    assert_equal "[Date]", field.type.to_type_signature
    assert_equal "list.date", metafield_directive_type_for(field)
  end

  def test_builds_date_time_field
    field = shop_schema.get_type("ProductExtensions").get_field("dateTime")
    assert_equal "DateTime", field.type.to_type_signature
    assert_equal "date_time", metafield_directive_type_for(field)
  end

  def test_builds_date_time_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("dateTimeList")
    assert_equal "[DateTime]", field.type.to_type_signature
    assert_equal "list.date_time", metafield_directive_type_for(field)
  end

  def test_builds_decimal_field
    field = shop_schema.get_type("ProductExtensions").get_field("decimal")
    assert_equal "Float", field.type.to_type_signature
    assert_equal "number_decimal", metafield_directive_type_for(field)
  end

  def test_builds_decimal_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("decimalList")
    assert_equal "[Float]", field.type.to_type_signature
    assert_equal "list.number_decimal", metafield_directive_type_for(field)
  end

  def test_builds_dimension_field
    field = shop_schema.get_type("ProductExtensions").get_field("dimension")
    assert_equal "DimensionMetatype", field.type.to_type_signature
    assert_equal "dimension", metafield_directive_type_for(field)
  end

  def test_builds_dimension_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("dimensionList")
    assert_equal "[DimensionMetatype]", field.type.to_type_signature
    assert_equal "list.dimension", metafield_directive_type_for(field)
  end

  def test_builds_file_reference_field
    field = shop_schema.get_type("ProductExtensions").get_field("fileReference")
    assert_equal "File", field.type.to_type_signature
    assert_equal "file_reference", metafield_directive_type_for(field)
  end

  def test_builds_file_reference_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("fileReferenceList")
    assert_equal "FileConnection", field.type.to_type_signature
    assert_equal "list.file_reference", metafield_directive_type_for(field)
  end

  def test_builds_id_field
    field = shop_schema.get_type("ProductExtensions").get_field("identity")
    assert_equal "ID", field.type.to_type_signature
    assert_equal "id", metafield_directive_type_for(field)
  end

  def test_builds_integer_field
    field = shop_schema.get_type("ProductExtensions").get_field("integer")
    assert_equal "Int", field.type.to_type_signature
    assert_equal "number_integer", metafield_directive_type_for(field)
  end

  def test_builds_integer_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("integerList")
    assert_equal "[Int]", field.type.to_type_signature
    assert_equal "list.number_integer", metafield_directive_type_for(field)
  end

  def test_builds_json_field
    field = shop_schema.get_type("ProductExtensions").get_field("json")
    assert_equal "JSON", field.type.to_type_signature
    assert_equal "json", metafield_directive_type_for(field)
  end

  def test_builds_language_field
    field = shop_schema.get_type("ProductExtensions").get_field("language")
    assert_equal "LanguageCode", field.type.to_type_signature
    assert_equal "language", metafield_directive_type_for(field)
  end

  def test_builds_link_field
    field = shop_schema.get_type("ProductExtensions").get_field("link")
    assert_equal "Link", field.type.to_type_signature
    assert_equal "link", metafield_directive_type_for(field)
  end

  def test_builds_link_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("linkList")
    assert_equal "[Link]", field.type.to_type_signature
    assert_equal "list.link", metafield_directive_type_for(field)
  end

  def test_builds_metaobject_reference_field
    field = shop_schema.get_type("ProductExtensions").get_field("metaobjectReference")
    assert_equal "TacoMetaobject", field.type.to_type_signature
    assert_equal "metaobject_reference", metafield_directive_type_for(field)
  end

  def test_builds_metaobject_reference_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("metaobjectReferenceList")
    assert_equal "TacoMetaobjectConnection", field.type.to_type_signature
    assert_equal "list.metaobject_reference", metafield_directive_type_for(field)
  end

  def test_builds_mixed_reference_field
    field = shop_schema.get_type("ProductExtensions").get_field("mixedReference")
    assert_equal "MixedMetaobject9C79", field.type.to_type_signature
    assert_equal "mixed_reference", metafield_directive_type_for(field)
  end

  def test_builds_mixed_reference_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("mixedReferenceList")
    assert_equal "MixedMetaobject9C79Connection", field.type.to_type_signature
    assert_equal "list.mixed_reference", metafield_directive_type_for(field)
  end

  def test_builds_money_field
    field = shop_schema.get_type("ProductExtensions").get_field("money")
    assert_equal "MoneyV2", field.type.to_type_signature
    assert_equal "money", metafield_directive_type_for(field)
  end

  def test_builds_multi_line_text_field
    field = shop_schema.get_type("ProductExtensions").get_field("multiLineText")
    assert_equal "String", field.type.to_type_signature
    assert_equal "multi_line_text_field", metafield_directive_type_for(field)
  end

  def test_builds_order_reference_field
    field = shop_schema.get_type("ProductExtensions").get_field("orderReference")
    assert_equal "Order", field.type.to_type_signature
    assert_equal "order_reference", metafield_directive_type_for(field)
  end

  def test_builds_page_reference_field
    field = shop_schema.get_type("ProductExtensions").get_field("pageReference")
    assert_equal "Page", field.type.to_type_signature
    assert_equal "page_reference", metafield_directive_type_for(field)
  end

  def test_builds_page_reference_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("pageReferenceList")
    assert_equal "PageConnection", field.type.to_type_signature
    assert_equal "list.page_reference", metafield_directive_type_for(field)
  end

  def test_builds_product_reference_field
    field = shop_schema.get_type("ProductExtensions").get_field("productReference")
    assert_equal "Product", field.type.to_type_signature
    assert_equal "product_reference", metafield_directive_type_for(field)
  end

  def test_builds_product_reference_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("productReferenceList")
    assert_equal "ProductConnection", field.type.to_type_signature
    assert_equal "list.product_reference", metafield_directive_type_for(field)
  end

  def test_builds_product_taxonomy_value_reference_field
    field = shop_schema.get_type("ProductExtensions").get_field("productTaxonomyValueReference")
    assert_equal "TaxonomyValue", field.type.to_type_signature
    assert_equal "product_taxonomy_value_reference", metafield_directive_type_for(field)
  end

  def test_builds_product_taxonomy_value_reference_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("productTaxonomyValueReferenceList")
    assert_equal "TaxonomyValueConnection", field.type.to_type_signature
    assert_equal "list.product_taxonomy_value_reference", metafield_directive_type_for(field)
  end

  def test_builds_rating_field
    field = shop_schema.get_type("ProductExtensions").get_field("rating")
    assert_equal "RatingMetatype", field.type.to_type_signature
    assert_equal "rating", metafield_directive_type_for(field)
  end

  def test_builds_rating_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("ratingList")
    assert_equal "[RatingMetatype]", field.type.to_type_signature
    assert_equal "list.rating", metafield_directive_type_for(field)
  end

  def test_builds_rich_text_field
    field = shop_schema.get_type("ProductExtensions").get_field("richText")
    assert_equal "RichTextMetatype", field.type.to_type_signature
    assert_equal "rich_text_field", metafield_directive_type_for(field)
  end

  def test_builds_single_line_text_field
    field = shop_schema.get_type("ProductExtensions").get_field("singleLineText")
    assert_equal "String", field.type.to_type_signature
    assert_equal "single_line_text_field", metafield_directive_type_for(field)
  end

  def test_builds_single_line_text_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("singleLineTextList")
    assert_equal "[String]", field.type.to_type_signature
    assert_equal "list.single_line_text_field", metafield_directive_type_for(field)
  end

  def test_builds_url_field
    field = shop_schema.get_type("ProductExtensions").get_field("url")
    assert_equal "URL", field.type.to_type_signature
    assert_equal "url", metafield_directive_type_for(field)
  end

  def test_builds_url_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("urlList")
    assert_equal "[URL]", field.type.to_type_signature
    assert_equal "list.url", metafield_directive_type_for(field)
  end

  def test_builds_variant_reference_field
    field = shop_schema.get_type("ProductExtensions").get_field("variantReference")
    assert_equal "ProductVariant", field.type.to_type_signature
    assert_equal "variant_reference", metafield_directive_type_for(field)
  end

  def test_builds_variant_reference_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("variantReferenceList")
    assert_equal "ProductVariantConnection", field.type.to_type_signature
    assert_equal "list.variant_reference", metafield_directive_type_for(field)
  end

  def test_builds_volume_field
    field = shop_schema.get_type("ProductExtensions").get_field("volume")
    assert_equal "VolumeMetatype", field.type.to_type_signature
    assert_equal "volume", metafield_directive_type_for(field)
  end

  def test_builds_volume_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("volumeList")
    assert_equal "[VolumeMetatype]", field.type.to_type_signature
    assert_equal "list.volume", metafield_directive_type_for(field)
  end

  def test_builds_weight_field
    field = shop_schema.get_type("ProductExtensions").get_field("weight")
    assert_equal "Weight", field.type.to_type_signature
    assert_equal "weight", metafield_directive_type_for(field)
  end

  def test_builds_weight_list_field
    field = shop_schema.get_type("ProductExtensions").get_field("weightList")
    assert_equal "[Weight]", field.type.to_type_signature
    assert_equal "list.weight", metafield_directive_type_for(field)
  end

  private

  def metafield_directive_type_for(field)
    field.directives.find { _1.graphql_name == "metafield" }.arguments.keyword_arguments[:type]
  end
end
