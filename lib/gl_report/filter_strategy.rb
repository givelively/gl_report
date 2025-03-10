# frozen_string_literal: true

require 'active_support/core_ext/object/blank'

module GlReport
  class FilterStrategy
    def initialize(column_definition)
      @column_definition = column_definition
    end

    def sql_filterable?
      # A column is SQL-filterable if it has a select and is not marked as select_only
      @column_definition[:select].present? && !@column_definition[:select_only]
    end

    def apply_to_relation(relation, operator, value)
      return relation unless sql_filterable?

      sql_fragment = @column_definition[:select].values.first
      sql_operator = convert_operator_to_sql(operator)

      relation.where("#{sql_fragment} #{sql_operator} ?", normalize_value(value))
    end

    def matches?(record_value, operator, target_value)
      operator = operator.to_sym
      case operator
      when :eq   then record_value == target_value
      when :gt   then record_value.respond_to?(:<) && record_value > target_value
      when :gte  then record_value.respond_to?(:<=) && record_value >= target_value
      when :lt   then record_value.respond_to?(:<) && record_value < target_value
      when :lte  then record_value.respond_to?(:<=) && record_value <= target_value
      when :like then record_value.to_s.include?(target_value.to_s)
      else
        raise Error, "Unsupported filter operator: #{operator}"
      end
    end

    private

    def convert_operator_to_sql(operator)
      case operator.to_sym
      when :eq   then '='
      when :gt   then '>'
      when :gte  then '>='
      when :lt   then '<'
      when :lte  then '<='
      when :like then 'LIKE'
      else
        raise Error, "Unsupported filter operator: #{operator}"
      end
    end

    def normalize_value(value)
      return "%#{value}%" if @current_operator == :like

      value
    end
  end
end
