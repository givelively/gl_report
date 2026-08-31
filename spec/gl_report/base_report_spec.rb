# frozen_string_literal: true

RSpec.describe GlReport::BaseReport do
  let(:test_model) do
    Class.new do
      class << self
        def all
          self
        end

        def where(*)
          self
        end

        def table_name
          'test_models'
        end

        def primary_key
          'id'
        end

        def left_outer_joins(*)
          self
        end

        def group(*)
          self
        end

        def select(*)
          self
        end

        def merge(*)
          self
        end

        def to_a
          [{ id: 1, simple_value: 'val', amount: 100 }]
        end
      end
    end
  end

  let(:report_class) do
    model = test_model
    Class.new(described_class) do
      model model

      column :simple_column,
             name: 'Simple Column',
             value: ->(record, _) { record[:simple_value] }

      column :sql_column,
             name: 'SQL Column',
             select: { amount: 'test_models.amount' },
             value: ->(record, _) { record[:amount] }

      column :virtual_with_select,
             name: 'Virtual with Select',
             select: { amount: 'test_models.amount' },
             select_only: true,
             value: ->(record, _) { "$#{record[:amount]}" }

      column :default_value_col,
             name: 'Default Value Column',
             select: { default_value_col: 'test_models.default_value_col' }
    end
  end

  describe '.model' do
    it 'sets and gets the model class' do
      expect(report_class.model).to eq(test_model)
    end

    it 'inherits model from parent class in subclass' do
      subclass = Class.new(report_class)
      expect(subclass.model).to eq(test_model)
    end
  end

  describe '._columns' do
    subject(:columns) { report_class._columns }

    it 'stores column definitions' do
      expect(columns.keys).to match_array(%i[simple_column sql_column virtual_with_select default_value_col])
    end

    it 'stores column options' do
      expect(columns[:sql_column][:name]).to eq('SQL Column')
      expect(columns[:sql_column][:select]).to eq(amount: 'test_models.amount')
    end

    it 'supports select directly on the report class' do
      filtered = report_class.select(:simple_column)
      expect(filtered).to be_a(GlReport::FilteredRelation)
      expect(filtered.selected_columns).to eq([:simple_column])
    end

    it 'assigns default value proc when omitted' do
      expect(columns[:default_value_col][:value]).to be_a(Proc)
      record_hash = { default_value_col: 'hello' }
      expect(columns[:default_value_col][:value].call(record_hash, nil)).to eq('hello')

      record_obj = Struct.new(:default_value_col).new('world')
      expect(columns[:default_value_col][:value].call(record_obj, nil)).to eq('world')

      custom_obj = Class.new do
        def default_value_col
          'poro'
        end
      end.new
      expect(columns[:default_value_col][:value].call(custom_obj, nil)).to eq('poro')
    end

    it 'inherits columns from parent class in subclass' do
      subclass = Class.new(report_class) do
        column :extra_column, value: ->(r, _) { r[:extra] }
      end
      expect(subclass._columns.keys).to match_array(
        %i[simple_column sql_column virtual_with_select default_value_col extra_column]
      )
      expect(report_class._columns.keys).not_to include(:extra_column)
    end
  end

  describe '.report_relation' do
    subject(:relation) { report_class.report_relation }

    it 'includes necessary selects' do
      allow(test_model).to receive(:select).and_call_original
      relation

      expect(test_model).to have_received(:select).with('test_models.id AS id')
      expect(test_model).to have_received(:select).with('test_models.amount AS amount')
    end

    context 'when model is not defined' do
      let(:report_class) { Class.new(described_class) }

      it 'raises an error' do
        expect { relation }.to raise_error(GlReport::Error, /Model is not defined/)
      end
    end
  end

  describe 'instance methods' do
    let(:instance) { report_class.new }

    it 'supports where filtering on instances' do
      filtered = instance.where(sql_column: { gt: 50 })
      expect(filtered).to be_a(GlReport::FilteredRelation)
    end

    it 'supports select on instances' do
      filtered = instance.select(:simple_column)
      expect(filtered).to be_a(GlReport::FilteredRelation)
      expect(filtered.selected_columns).to eq([:simple_column])
    end

    it 'supports scope in initialize with where and select chaining' do
      scoped_report = report_class.new(scope: test_model)
      expect(scoped_report.scope).to eq(test_model)
      expect(scoped_report.where(sql_column: { gt: 10 })).to be_a(GlReport::FilteredRelation)
      expect(scoped_report.select(:simple_column)).to be_a(GlReport::FilteredRelation)
      results = scoped_report.run
      expect(results).to be_an(Array)
    end
  end
end
