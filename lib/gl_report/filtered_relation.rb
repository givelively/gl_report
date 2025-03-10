# frozen_string_literal: true

module GlReport
  class FilteredRelation
    attr_reader :relation, :report_class, :pending_filters

    def initialize(relation, report_class)
      @relation = relation
      @report_class = report_class
      @pending_filters = {}
    end

    def where(conditions)
      new_filters = conditions.dup
      new_relation = relation

      # Apply SQL filters where possible
      conditions.each do |column_key, operators|
        column_def = report_class._columns[column_key]
        raise Error, "Unknown column: #{column_key}" unless column_def

        strategy = FilterStrategy.new(column_def)
        
        if strategy.sql_filterable?
          operators.each do |operator, value|
            new_relation = strategy.apply_to_relation(new_relation, operator, value)
          end
          new_filters.delete(column_key)
        end
      end

      # Store remaining filters for post-processing
      FilteredRelation.new(new_relation, report_class).tap do |fr|
        fr.pending_filters.merge!(new_filters)
      end
    end

    def run
      report = report_class.new
      results = to_a.map { |record| report.computed_row(record) }

      return results if pending_filters.empty?

      # Apply any remaining virtual filters
      results.select do |row|
        pending_filters.all? do |column_key, operators|
          column_def = report_class._columns[column_key]
          strategy = FilterStrategy.new(column_def)
          
          operators.all? do |operator, target_value|
            strategy.matches?(row[column_key], operator, target_value)
          end
        end
      end
    end

    def to_a
      relation.to_a
    end

    def method_missing(method, *args, &block)
      if relation.respond_to?(method)
        new_relation = relation.send(method, *args, &block)
        FilteredRelation.new(new_relation, report_class).tap do |fr|
          fr.pending_filters.merge!(pending_filters)
        end
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      relation.respond_to?(method) || super
    end
  end
end
