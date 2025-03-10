# frozen_string_literal: true

module GlReport
  class BaseReport
    class << self
      def model(klass = nil)
        if klass
          @model = klass
        else
          @model
        end
      end

      def column(key, options = {})
        _columns[key] = options
      end

      def _columns
        @_columns ||= {}
      end

      def where(conditions)
        FilteredRelation.new(report_relation, self).where(conditions)
      end

      def report_relation
        raise Error, "Model is not defined for #{name}" unless _model

        relation = _model.all

        # Apply any joins defined in the column options
        _columns.each_value do |opts|
          relation = relation.left_outer_joins(opts[:joins]) if opts[:joins]
        end

        # Always select the primary id
        relation = relation.select("#{_model.table_name}.id AS id")

        # Add selects for all columns that need database data
        used_selects = {}
        _columns.each_value do |opts|
          next unless opts[:select]

          opts[:select].each do |alias_name, sql_fragment|
            next if used_selects[alias_name]

            used_selects[alias_name] = true
            relation = relation.select("#{sql_fragment} AS #{alias_name}")
          end
        end

        relation
      end

      protected

      def _model
        @model
      end
    end

    attr_reader :scope

    def initialize(scope: nil)
      @scope = scope
    end

    def run
      relation = self.class.report_relation
      relation = relation.merge(scope) if scope
      relation.to_a.map { |record| computed_row(record) }
    end

    def computed_row(record)
      self.class._columns.transform_values do |column_def|
        column_def[:value].call(record, self)
      end
    end
  end
end
