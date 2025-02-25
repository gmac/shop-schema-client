# frozen_string_literal: true

module ShopSchemaClient
  class SchemaComposer
    class MetaobjectSet
      attr_reader :metaobject_definitions

      def initialize(metaobject_defs)
        @metaobject_definitions = metaobject_defs.sort_by(&:type)
      end

      def ==(other)
        @metaobject_definitions == other.metaobject_definitions
      end

      def typename
        @typename ||= begin
          member_names = @metaobject_definitions.map { MetafieldTypeResolver.metaobject_typename(_1.type) }
          member_identity = Digest::MD5.hexdigest(member_names.join("/")).slice(0..3)
          "MixedMetaobject#{member_identity.upcase}"
        end
      end
    end
  end
end
