# frozen_string_literal: true

module GlReport
  class FilteredRelation
    include Enumerable

    attr_reader :relation, :report_class, :selected_columns, :pending_filters

    def initialize(relation, report_class, selected_columns: nil, pending_filters: {})
      @relation = relation
      @report_class = report_class
      @selected_columns = selected_columns
      @pending_filters = pending_filters.dup
    end

    def where(conditions)
      new_filters = conditions.dup
      new_relation = relation

      # Apply SQL filters where possible
      conditions.each do |column_key, operators|
        column_def = report_class._columns[column_key]
        raise Error, "Unknown column: #{column_key}" unless column_def

        strategy = FilterStrategy.new(column_def)
        next unless strategy.sql_filterable?

        operators.each do |operator, value|
          new_relation = strategy.apply_to_relation(new_relation, operator, value)
        end
        new_filters.delete(column_key)
      end

      # Store remaining filters for post-processing
      FilteredRelation.new(
        new_relation,
        report_class,
        selected_columns: selected_columns,
        pending_filters: pending_filters.merge(new_filters)
      )
    end

    def select(*columns)
      cols = columns.flatten
      FilteredRelation.new(
        relation,
        report_class,
        selected_columns: cols,
        pending_filters: pending_filters
      )
    end

    def each(&)
      run.each(&)
    end

    def run
      report = report_class.new
      needed_columns = if selected_columns && pending_filters.present?
                         (selected_columns + pending_filters.keys).uniq
                       else
                         selected_columns
                       end

      results = to_a.map { |record| report.computed_row(record, needed_columns) }

      filtered = apply_pending_filters(results)

      if selected_columns
        filtered.map { |row| row.slice(*selected_columns) }
      else
        filtered
      end
    end

    def to_a
      relation.to_a
    end

    def method_missing(method, ...)
      if relation.respond_to?(method)
        new_relation = relation.public_send(method, ...)
        FilteredRelation.new(
          new_relation,
          report_class,
          selected_columns: selected_columns,
          pending_filters: pending_filters
        )
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      relation.respond_to?(method) || super
    end

    private

    def apply_pending_filters(results)
      return results if pending_filters.empty?

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
  end
end
