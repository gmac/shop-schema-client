# frozen_string_literal: true

module ShopSchemaClient
  class RequestTransformer
    class FieldTransform
      attr_reader :metafield_type, :selections

      def initialize(metafield_type, selections: nil)
        @metafield_type = metafield_type
        @selections = selections
      end

      def merge(other)
        if other.nil? || other.metafield_type != @metafield_type
          # GraphQL validates overlapping field selections for consistency, so this shouldn't happen.
          # If it does, it probably means one of a few possibilities:
          # 1. The query wasn't validated. Run static validatations and return errors.
          # 2. The query slips through a known bug in GraphQL Ruby's overlapping fields validation,
          #    see: https://github.com/rmosolgo/graphql-ruby/issues/4403. While Admin API allows this,
          #    we have to be more strict about it.
          raise ValidationError, "overlapping field selections must be the same"
        end
        if other.selections
          @selections ||= []
          @selections.push(*other.selections)
          @selections.tap(&:uniq!)
        end
      end

      def as_json
        {
          "t" => @metafield_type,
          "s" => @selections,
        }.tap(&:compact!)
      end
    end

    class TransformationScope
      attr_reader :parent, :fields, :possible_types
      attr_accessor :field_transform

      def initialize(parent = nil)
        @parent = parent
        @possible_types = {}
        @fields = {}
        @field_transform = nil
      end

      def as_json
        fields = @fields.each_with_object({}) do |(k, v), m|
          info = v.as_json
          m[k] = info unless info.empty?
        end

        possible_types = @possible_types.each_with_object({}) do |(k, v), m|
          info = v.as_json
          m[k] = info unless info.empty?
        end

        {
          "f" => fields.empty? ? nil : fields,
          "fx" => @field_transform&.as_json,
          "if" => possible_types.empty? ? nil : possible_types,
        }.tap(&:compact!)
      end
    end

    class TransformationMap
      attr_reader :current_scope

      def initialize
        @current_scope = TransformationScope.new
      end

      def as_json
        @current_scope.as_json
      end

      def apply_field_transform(transform)
        if @current_scope.field_transform
          @current_scope.field_transform.merge(transform)
        else
          @current_scope.field_transform = transform
        end
      end

      def field_breadcrumb(ns)
        @current_scope = @current_scope.fields[ns] ||= TransformationScope.new(@current_scope)
        result = yield
        back
        result
      end

      def type_breadcrumb(types)
        @current_scope = @current_scope.possible_types[types] ||= TransformationScope.new(@current_scope)
        result = yield
        back
        result
      end

      private

      def back
        raise "TransformationMap cannot go back" if @current_scope.parent.nil?
        @current_scope = @current_scope.parent
      end
    end
  end
end
