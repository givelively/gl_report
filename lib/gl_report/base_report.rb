# frozen_string_literal: true

module GlReport
  class BaseReport
    class << self
      def model(klass = nil)
        if klass
          @model = klass
        else
          @model ||= superclass.respond_to?(:_model) ? superclass._model : nil
        end
      end

      def column(key, options = {})
        opts = options.dup
        opts[:value] ||= ->(record, _) { record_column_value(record, key) }
        _columns[key] = opts
      end

      def _columns
        @_columns ||= superclass.respond_to?(:_columns) ? superclass._columns.dup : {}
      end

      def where(conditions)
        FilteredRelation.new(report_relation, self).where(conditions)
      end

      def select(*columns)
        FilteredRelation.new(report_relation, self).select(*columns)
      end

      def report_relation
        raise Error, "Model is not defined for #{name || 'AnonymousReport'}" unless _model

        relation = _model.all
        relation = apply_column_joins(relation)
        relation = apply_primary_key_and_group(relation)
        apply_column_selects(relation)
      end

      def _model
        @model ||= superclass.respond_to?(:_model) ? superclass._model : nil
      end

      def record_column_value(record, key)
        if record.is_a?(Hash)
          record[key] || record[key.to_s]
        elsif record.respond_to?(:[])
          record[key] || (record.respond_to?(key) ? record.public_send(key) : nil)
        elsif record.respond_to?(key)
          record.public_send(key)
        end
      end

      private

      def apply_column_joins(relation)
        _columns.each_value do |opts|
          relation = relation.left_outer_joins(opts[:joins]) if opts[:joins]
        end
        relation
      end

      def apply_primary_key_and_group(relation)
        pk = _model.respond_to?(:primary_key) && _model.primary_key ? _model.primary_key : 'id'
        table = _model.respond_to?(:table_name) ? _model.table_name : _model.to_s.tableize
        relation = relation.select("#{table}.#{pk} AS id")
        relation = relation.group("#{table}.#{pk}") if relation.respond_to?(:group)
        relation
      end

      def apply_column_selects(relation)
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

    def where(conditions)
      relation = self.class.report_relation
      relation = relation.merge(scope) if scope
      FilteredRelation.new(relation, self.class).where(conditions)
    end

    def select(*columns)
      relation = self.class.report_relation
      relation = relation.merge(scope) if scope
      FilteredRelation.new(relation, self.class).select(*columns)
    end

    def computed_row(record, selected_columns = nil)
      columns = if selected_columns
                  self.class._columns.slice(*selected_columns)
                else
                  self.class._columns
                end

      columns.transform_values { |column_def| column_def[:value].call(record, self) }
    end
  end
end
