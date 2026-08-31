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

        def limit(*)
          self
        end

        def count(*)
          2
        end

        def size
          2
        end

        def empty?
          false
        end

        def to_a
          [
            { id: 1, amount: 100, status: 'active' },
            { id: 2, amount: 200, status: 'inactive' }
          ]
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

      column :status,
             select: { status: 'test_models.status' },
             value: ->(record, _) { record[:status] }

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

    it 'preserves selected_columns when chaining where after select' do
      chained = filtered_relation.select(:amount).where(status: { eq: 'active' })
      expect(chained.selected_columns).to eq([:amount])
    end

    it 'deep merges pending filters when multiple where calls are chained on the same virtual column' do
      chained = filtered_relation
                .where(formatted_amount: { not_eq: '$100' })
                .where(formatted_amount: { not_eq: '$300' })

      expect(chained.pending_filters[:formatted_amount]).to eq(
        not_eq: '$300'
      )
    end

    it 'combines multiple distinct operators on the same virtual column' do
      chained = filtered_relation
                .where(formatted_amount: { gt: '$050' })
                .where(formatted_amount: { lt: '$150' })

      expect(chained.pending_filters[:formatted_amount]).to eq(
        gt: '$050',
        lt: '$150'
      )
      expect(chained.run).to eq(
        [{ amount: 100, status: 'active', formatted_amount: '$100' }]
      )
    end
  end

  describe '#select' do
    it 'preserves pending_filters when chaining select after where' do
      chained = filtered_relation.where(formatted_amount: { eq: '$100' }).select(:amount)
      expect(chained.pending_filters).to include(:formatted_amount)
      expect(chained.selected_columns).to eq([:amount])
    end
  end

  describe '#run' do
    it 'filters correctly with virtual-only column and selected_columns' do
      results = filtered_relation
                .where(formatted_amount: { eq: '$200' })
                .select(:amount)
                .run

      expect(results).to eq([{ amount: 200 }])
    end
  end

  describe 'counting and sizing' do
    it 'delegates count directly to relation when no pending virtual filters' do
      allow(relation).to receive(:count).and_return(5)
      expect(filtered_relation.count).to eq(5)
      expect(relation).to have_received(:count)
    end

    it 'evaluates count over filtered results when virtual filters exist' do
      chained = filtered_relation.where(formatted_amount: { eq: '$100' })
      expect(chained.count).to eq(1)
    end

    it 'evaluates count with a block' do
      expect(filtered_relation.count { |r| r[:amount] > 150 }).to eq(1)
    end

    it 'supports size, length, and empty?' do
      expect(filtered_relation.size).to eq(2)
      expect(filtered_relation.length).to eq(2)
      expect(filtered_relation.empty?).to be false

      chained = filtered_relation.where(formatted_amount: { eq: '$999' })
      expect(chained.size).to eq(0)
      expect(chained.empty?).to be true
    end
  end

  describe 'Enumerable' do
    it 'supports map, each directly' do
      amounts = filtered_relation.map { |r| r[:amount] }
      expect(amounts).to eq([100, 200])
    end
  end

  describe 'delegation via method_missing' do
    it 'delegates unknown methods that the relation responds to' do
      allow(relation).to receive(:limit).and_return(relation)
      chained = filtered_relation.limit(5)
      expect(chained).to be_a(GlReport::FilteredRelation)
      expect(relation).to have_received(:limit).with(5)
    end

    it 'raises NoMethodError for methods the relation does not respond to' do
      expect { filtered_relation.non_existent_method_xyz }.to raise_error(NoMethodError)
    end

    it 'responds to methods that relation responds to' do
      expect(filtered_relation.respond_to?(:where)).to be true
      expect(filtered_relation.respond_to?(:non_existent_xyz)).to be false
    end
  end
end
