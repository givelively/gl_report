# frozen_string_literal: true

require 'active_support/core_ext/object/blank'

module GlReport
  class FilterStrategy
    OPERATOR_SQL_MAP = {
      eq: '=', ne: '!=', not_eq: '!=',
      gt: '>', gte: '>=', lt: '<', lte: '<=',
      like: 'LIKE', ilike: 'ILIKE',
      in: 'IN', not_in: 'NOT IN'
    }.freeze

    ORDERED_COMPARATORS = { gt: :>, gte: :>=, lt: :<, lte: :<= }.freeze

    def initialize(column_definition)
      @column_definition = column_definition
    end

    def sql_filterable?
      @column_definition[:select].present? && !@column_definition[:select_only]
    end

    def apply_to_relation(relation, operator, value)
      return relation unless sql_filterable?

      sql_fragment = @column_definition[:select].values.first
      sql_operator = convert_operator_to_sql(operator, value)
      normalized_val = normalize_value(value, operator)

      if value.nil? && %i[eq not_eq ne].include?(operator.to_sym)
        relation.where("#{sql_fragment} #{sql_operator}")
      elsif %i[in not_in].include?(operator.to_sym)
        relation.where("#{sql_fragment} #{sql_operator} (?)", normalized_val)
      else
        relation.where("#{sql_fragment} #{sql_operator} ?", normalized_val)
      end
    end

    def matches?(record_value, operator, target_value)
      op = operator.to_sym
      case op
      when :eq          then record_value == target_value
      when :not_eq, :ne then record_value != target_value
      when :gt, :gte, :lt, :lte then compare_ordered(record_value, op, target_value)
      when :like        then string_matches?(record_value, target_value, case_sensitive: true)
      when :ilike       then string_matches?(record_value, target_value, case_sensitive: false)
      when :in          then Array(target_value).include?(record_value)
      when :not_in      then !Array(target_value).include?(record_value)
      else
        raise Error, "Unsupported filter operator: #{operator}"
      end
    end

    private

    def string_matches?(record_val, target_val, case_sensitive:)
      return false if record_val.nil? || target_val.nil?

      if case_sensitive
        record_val.to_s.include?(target_val.to_s)
      else
        record_val.to_s.downcase.include?(target_val.to_s.downcase)
      end
    end

    def compare_ordered(record_value, operator, target_value)
      return false if record_value.nil? || target_value.nil?

      comparator = ORDERED_COMPARATORS[operator]
      record_value.respond_to?(comparator) && record_value.public_send(comparator, target_value)
    end

    def convert_operator_to_sql(operator, value = nil)
      op = operator.to_sym
      if value.nil?
        return 'IS NULL' if op == :eq
        return 'IS NOT NULL' if %i[ne not_eq].include?(op)
      end

      OPERATOR_SQL_MAP[op] || (raise Error, "Unsupported filter operator: #{operator}")
    end

    def normalize_value(value, operator)
      return "%#{value}%" if %i[like ilike].include?(operator.to_sym)
      return Array(value) if %i[in not_in].include?(operator.to_sym)

      value
    end
  end
end
