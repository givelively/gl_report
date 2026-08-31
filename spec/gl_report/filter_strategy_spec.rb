# frozen_string_literal: true

RSpec.describe GlReport::FilterStrategy do
  let(:column_definition) { {} }
  subject(:strategy) { described_class.new(column_definition) }

  describe '#sql_filterable?' do
    context 'when column has select and no select_only flag' do
      let(:column_definition) do
        { select: { amount: 'orders.amount' } }
      end

      it 'returns true' do
        expect(strategy.sql_filterable?).to be true
      end
    end

    context 'when column has select but marked as select_only' do
      let(:column_definition) do
        { select: { amount: 'orders.amount' }, select_only: true }
      end

      it 'returns false' do
        expect(strategy.sql_filterable?).to be false
      end
    end

    context 'when column has no select' do
      let(:column_definition) do
        { value: ->(record, _) { record[:amount] } }
      end

      it 'returns false' do
        expect(strategy.sql_filterable?).to be false
      end
    end
  end

  describe '#matches?' do
    {
      eq: [
        { value: 100, target: 100, expected: true },
        { value: 100, target: 200, expected: false },
        { value: nil, target: nil, expected: true },
        { value: 100, target: nil, expected: false },
        { value: false, target: false, expected: true },
        { value: false, target: true, expected: false }
      ],
      ne: [
        { value: 100, target: 200, expected: true },
        { value: 100, target: 100, expected: false }
      ],
      not_eq: [
        { value: 100, target: 200, expected: true },
        { value: 100, target: 100, expected: false }
      ],
      gt: [
        { value: 200, target: 100, expected: true },
        { value: 100, target: 200, expected: false },
        { value: nil, target: 100, expected: false }
      ],
      gte: [
        { value: 200, target: 100, expected: true },
        { value: 100, target: 100, expected: true },
        { value: 50, target: 100, expected: false },
        { value: nil, target: 100, expected: false }
      ],
      lt: [
        { value: 50, target: 100, expected: true },
        { value: 100, target: 100, expected: false },
        { value: nil, target: 100, expected: false }
      ],
      lte: [
        { value: 50, target: 100, expected: true },
        { value: 100, target: 100, expected: true },
        { value: 200, target: 100, expected: false },
        { value: nil, target: 100, expected: false }
      ],
      like: [
        { value: 'hello world', target: 'hello', expected: true },
        { value: 'hello world', target: 'Hello', expected: false },
        { value: 'hello world', target: 'goodbye', expected: false },
        { value: nil, target: 'test', expected: false },
        { value: 'test', target: nil, expected: false }
      ],
      ilike: [
        { value: 'Hello World', target: 'hello', expected: true },
        { value: 'Hello World', target: 'WORLD', expected: true },
        { value: 'hello world', target: 'goodbye', expected: false },
        { value: nil, target: 'test', expected: false },
        { value: 'test', target: nil, expected: false }
      ],
      in: [
        { value: 'completed', target: %w[completed pending], expected: true },
        { value: 'failed', target: %w[completed pending], expected: false }
      ],
      not_in: [
        { value: 'failed', target: %w[completed pending], expected: true },
        { value: 'completed', target: %w[completed pending], expected: false }
      ]
    }.each do |operator, test_cases|
      context "with #{operator} operator" do
        test_cases.each do |test_case|
          desc = "returns #{test_case[:expected]} when comparing #{test_case[:value].inspect} " \
                 "with #{test_case[:target].inspect}"
          it desc do
            expect(strategy.matches?(test_case[:value], operator, test_case[:target]))
              .to eq(test_case[:expected])
          end
        end
      end
    end

    it 'raises error for unsupported operator' do
      expect { strategy.matches?(100, :unknown, 200) }
        .to raise_error(GlReport::Error, 'Unsupported filter operator: unknown')
    end
  end

  describe '#apply_to_relation' do
    let(:column_definition) { { select: { amount: 'orders.amount' } } }
    let(:relation) { double('Relation', where: nil) }

    it 'formats LIKE query with wildcards' do
      allow(relation).to receive(:where).and_return(relation)
      strategy.apply_to_relation(relation, :like, 'term')
      expect(relation).to have_received(:where).with('orders.amount LIKE ?', '%term%')
    end

    it 'formats ILIKE query with LOWER for database agnosticism' do
      allow(relation).to receive(:where).and_return(relation)
      strategy.apply_to_relation(relation, :ilike, 'Term')
      expect(relation).to have_received(:where).with('LOWER(orders.amount) LIKE ?', '%term%')
    end

    it 'handles IS NULL for nil equality' do
      allow(relation).to receive(:where).and_return(relation)
      strategy.apply_to_relation(relation, :eq, nil)
      expect(relation).to have_received(:where).with('orders.amount IS NULL')
    end

    it 'handles IS NOT NULL for nil inequality' do
      allow(relation).to receive(:where).and_return(relation)
      strategy.apply_to_relation(relation, :not_eq, nil)
      expect(relation).to have_received(:where).with('orders.amount IS NOT NULL')
    end

    it 'handles nil for LIKE queries by returning 1 = 0' do
      allow(relation).to receive(:where).and_return(relation)
      strategy.apply_to_relation(relation, :like, nil)
      expect(relation).to have_received(:where).with('1 = 0')
    end

    it 'handles nil for ordered queries (gt, gte, lt, lte) by returning 1 = 0' do
      allow(relation).to receive(:where).and_return(relation)
      strategy.apply_to_relation(relation, :gt, nil)
      expect(relation).to have_received(:where).with('1 = 0')
    end

    it 'handles IN queries' do
      allow(relation).to receive(:where).and_return(relation)
      strategy.apply_to_relation(relation, :in, [10, 20])
      expect(relation).to have_received(:where).with('orders.amount IN (?)', [10, 20])
    end
  end
end
