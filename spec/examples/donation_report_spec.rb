# frozen_string_literal: true

RSpec.describe 'Example: DonationReport' do
  # First define a minimal test schema
  before(:all) do
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')

    ActiveRecord::Schema.define do
      create_table :donors do |t|
        t.string :name
        t.string :email
        t.timestamps
      end

      create_table :donations do |t|
        t.references :donor
        t.decimal :amount, precision: 10, scale: 2
        t.string :currency, default: 'USD'
        t.string :status
        t.timestamps
      end
    end

    # Define basic AR models for testing
    class Donor < ActiveRecord::Base
      has_many :donations
    end

    class Donation < ActiveRecord::Base
      belongs_to :donor
    end
  end

  # Clean up after all tests
  after(:all) do
    ActiveRecord::Base.connection.drop_table(:donations)
    ActiveRecord::Base.connection.drop_table(:donors)
    Object.send(:remove_const, :Donor)
    Object.send(:remove_const, :Donation)
  end

  # Define our example report
  let(:report_class) do
    Class.new(GlReport::BaseReport) do
      model Donation

      column :donor_name,
             name: 'Donor Name',
             select: { donor_name: 'donors.name' },
             joins: :donor,
             value: ->(record, _) { record[:donor_name] }

      column :amount,
             name: 'Amount',
             select: { amount: 'donations.amount' },
             value: ->(record, _) { record[:amount] }

      column :formatted_amount,
             name: 'Formatted Amount',
             select: { amount: 'donations.amount', currency: 'donations.currency' },
             value: ->(record, report) { report.format_currency(record[:amount], record[:currency]) }

      column :status,
             name: 'Status',
             select: { status: 'donations.status' },
             value: ->(record, _) { record[:status]&.titleize }

      def format_currency(amount, currency)
        "#{currency} #{format('%.2f', amount)}"
      end
    end
  end

  let(:report) { report_class.new }

  before do
    # Set up test data
    donor = Donor.create!(
      name: 'Jane Doe',
      email: 'jane@example.com'
    )

    Donation.create!(
      donor: donor,
      amount: 100.50,
      status: 'completed'
    )

    Donation.create!(
      donor: donor,
      amount: 75.25,
      status: 'pending'
    )
  end

  describe 'basic reporting' do
    it 'returns all donations with formatted values' do
      results = report.run

      expect(results.size).to eq(2)
      expect(results.first).to include(
        donor_name: 'Jane Doe',
        amount: BigDecimal('100.50'),
        formatted_amount: 'USD 100.50',
        status: 'Completed'
      )
    end
  end

  describe 'filtering' do
    it 'filters by amount' do
      results = report_class.where(amount: { gt: 80 }).run

      expect(results.size).to eq(1)
      expect(results.first[:amount]).to eq(BigDecimal('100.50'))
    end

    it 'filters by status' do
      results = report_class.where(status: { eq: 'completed' }).run

      expect(results.size).to eq(1)
      expect(results.first[:status]).to eq('Completed')
    end
  end
end
