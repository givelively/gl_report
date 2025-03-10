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
        { value: 100, target: 200, expected: false }
      ],
      gt: [
        { value: 200, target: 100, expected: true },
        { value: 100, target: 200, expected: false }
      ],
      gte: [
        { value: 200, target: 100, expected: true },
        { value: 100, target: 100, expected: true },
        { value: 50, target: 100, expected: false }
      ],
      lt: [
        { value: 50, target: 100, expected: true },
        { value: 100, target: 100, expected: false }
      ],
      lte: [
        { value: 50, target: 100, expected: true },
        { value: 100, target: 100, expected: true },
        { value: 200, target: 100, expected: false }
      ],
      like: [
        { value: 'hello world', target: 'hello', expected: true },
        { value: 'hello world', target: 'goodbye', expected: false }
      ]
    }.each do |operator, test_cases|
      context "with #{operator} operator" do
        test_cases.each do |test_case|
          it "returns #{test_case[:expected]} when comparing #{test_case[:value]} with #{test_case[:target]}" do
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
end
