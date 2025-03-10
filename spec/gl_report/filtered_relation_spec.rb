# frozen_string_literal: true

RSpec.describe GlReport::FilteredRelation do
  let(:test_model) do
    Class.new do
      class << self
        def all
          self
        end

        def where(*)
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
    Class.new(GlReport::BaseReport) do
      model model

      column :amount,
             select: { amount: 'test_models.amount' },
             value: ->(record, _) { record[:amount] }

      column :formatted_amount,
             select: { amount: 'test_models.amount' },
             select_only: true,
             value: ->(record, _) { "$#{record[:amount]}" }
    end
  end

  let(:relation) { test_model.all }
  subject(:filtered_relation) { described_class.new(relation, report_class) }

  describe '#where' do
    context 'with SQL-filterable column' do
      it 'applies the filter to the relation' do
        allow(relation).to receive(:where).and_return(relation)

        filtered_relation.where(amount: { gt: 100 })

        expect(relation).to have_received(:where)
          .with('test_models.amount > ?', 100)
      end
    end

    context 'with unknown column' do
      it 'raises an error' do
        expect { filtered_relation.where(unknown: { eq: 100 }) }
          .to raise_error(GlReport::Error, 'Unknown column: unknown')
      end
    end

    context 'with virtual-only column' do
      it 'stores the filter for post-processing' do
        result = filtered_relation.where(formatted_amount: { eq: '$100' })
        expect(result.pending_filters).to include(:formatted_amount)
      end
    end
  end
end
