# frozen_string_literal: true

RSpec.describe GlReport::BaseReport do
  let(:test_model) do
    Class.new do
      class << self
        def all
          self
        end

        def table_name
          'test_models'
        end

        def left_outer_joins(*)
          self
        end

        def select(*)
          self
        end

        def to_a
          []
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
    end
  end

  describe '.model' do
    it 'sets and gets the model class' do
      expect(report_class.model).to eq(test_model)
    end
  end

  describe '._columns' do
    subject(:columns) { report_class._columns }

    it 'stores column definitions' do
      expect(columns.keys).to match_array(%i[simple_column sql_column virtual_with_select])
    end

    it 'stores column options' do
      expect(columns[:sql_column][:name]).to eq('SQL Column')
      expect(columns[:sql_column][:select]).to eq(amount: 'test_models.amount')
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
end
