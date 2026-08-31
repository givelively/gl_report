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

      def group_by(*columns)
        @_custom_groups = columns.flatten
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
        sym_key = key.to_sym
        str_key = key.to_s

        if record.is_a?(Hash) || record.respond_to?(:key?)
          return record[sym_key] if record.key?(sym_key)
          return record[str_key] if record.key?(str_key)
        elsif record.respond_to?(:[])
          val = safe_subscript(record, sym_key, str_key)
          return val unless val.nil?
        end

        record.respond_to?(sym_key) ? record.public_send(sym_key) : nil
      end

      private

      def safe_subscript(record, sym_key, str_key)
        val = begin
          record[sym_key]
        rescue StandardError
          nil
        end
        if val.nil?
          val = begin
            record[str_key]
          rescue StandardError
            nil
          end
        end
        val
      end

      def apply_column_joins(relation)
        _columns.each_value do |opts|
          relation = relation.left_outer_joins(opts[:joins]) if opts[:joins]
        end
        relation
      end

      def aggregate_report?
        return true if @_custom_groups.present?

        _columns.each_value.any? do |opts|
          opts[:select]&.each_value&.any? { |sql| sql.to_s =~ /\b(COUNT|SUM|AVG|MIN|MAX)\b/i }
        end
      end

      def apply_primary_key_and_group(relation)
        pk = _model.respond_to?(:primary_key) && _model.primary_key ? _model.primary_key : 'id'
        table = _model.respond_to?(:table_name) ? _model.table_name : _model.to_s.tableize
        relation = relation.select("#{table}.#{pk} AS id")

        if aggregate_report? && relation.respond_to?(:group)
          @_custom_groups.present? ? relation.group(*@_custom_groups) : relation.group("#{table}.#{pk}")
        else
          relation
        end
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
