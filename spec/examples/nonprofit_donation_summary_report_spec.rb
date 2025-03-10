RSpec.describe "Example: NonprofitDonationSummaryReport" do
  # Model definitions for testing
  class Nonprofit < ActiveRecord::Base
    has_many :donations, foreign_key: 'nonprofit_id'
  end

  class Donation < ActiveRecord::Base
    belongs_to :nonprofit
    has_one :refund, foreign_key: 'donation_id'
  end

  class Refund < ActiveRecord::Base
    belongs_to :donation
  end

  before(:all) do
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    
    ActiveRecord::Schema.define do
      create_table :nonprofits do |t|
        t.string :name
        t.timestamps
      end

      create_table :donations do |t|
        t.references :nonprofit
        t.integer :amount_cents, null: false
        t.string :currency, default: "USD"
        t.string :status
        t.datetime :processed_at
        t.timestamps
      end

      create_table :refunds do |t|
        t.references :donation
        t.integer :amount_cents, null: false
        t.string :status
        t.timestamps
      end
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.drop_table(:refunds)
    ActiveRecord::Base.connection.drop_table(:donations)
    ActiveRecord::Base.connection.drop_table(:nonprofits)
    Object.send(:remove_const, :Refund)
    Object.send(:remove_const, :Donation)
    Object.send(:remove_const, :Nonprofit)
  end

  let(:report_class) do
    Class.new(GlReport::BaseReport) do
      model Nonprofit  # Using our test model here

      column :nonprofit_name,
        name: "Nonprofit Name",
        select: { name: "nonprofits.name" },
        value: ->(record, _) { record[:name] }

      column :donation_processed_at,
        name: "Donation Date",
        select: { processed_at: "donations.processed_at" },
        joins: :donations,
        virtual: true,
        value: ->(record, _) { record[:processed_at] }

      column :donation_status,
        name: "Status",
        select: { status: "donations.status" },
        joins: :donations,
        virtual: true,
        value: ->(record, _) { record[:status] }

      column :total_donations,
        name: "Total Donations",
        select: { donation_count: "COUNT(DISTINCT donations.id)" },
        joins: :donations,
        value: ->(record, _) { record[:donation_count] }

      column :gross_amount_cents,
        name: "Gross Amount (cents)",
        select: { gross_cents: "COALESCE(SUM(donations.amount_cents), 0)" },
        joins: :donations,
        value: ->(record, _) { record[:gross_cents] }

      column :refund_amount_cents,
        name: "Refund Amount (cents)",
        select: { refunds_cents: "COALESCE(SUM(refunds.amount_cents), 0)" },
        joins: { donations: :refund },
        value: ->(record, _) { record[:refunds_cents] }

      column :net_amount_cents,
        name: "Net Amount (cents)",
        select: {
          donation_sum_cents: "COALESCE(SUM(donations.amount_cents), 0)",
          refund_sum_cents: "COALESCE(SUM(refunds.amount_cents), 0)"
        },
        joins: { donations: :refund },
        value: ->(record, _) { 
          record[:donation_sum_cents] - record[:refund_sum_cents]
        }
    end
  end

  let!(:nonprofit1) { Nonprofit.create!(name: "Save the Whales") }
  let!(:nonprofit2) { Nonprofit.create!(name: "Plant Trees") }

  let!(:donation1) do
    Donation.create!(
      nonprofit: nonprofit1,
      amount_cents: 10_000,
      status: "completed",
      processed_at: Time.utc(2025, 1, 15)
    )
  end

  let!(:donation2) do
    Donation.create!(
      nonprofit: nonprofit1,
      amount_cents: 20_000,
      status: "completed",
      processed_at: Time.utc(2025, 2, 20)
    )
  end

  let!(:donation3) do
    Donation.create!(
      nonprofit: nonprofit2,
      amount_cents: 15_000,
      status: "completed",
      processed_at: Time.utc(2025, 1, 1)
    )
  end

  let!(:refund1) do
    Refund.create!(
      donation: donation1,
      amount_cents: 5_000,
      status: "completed"
    )
  end

  describe "filtering" do
    it "filters by date range" do
      results = report_class
        .where(donation_status: { eq: "completed" })
        .where(donation_processed_at: { 
          gte: Time.utc(2025, 1, 1),
          lt: Time.utc(2025, 2, 1)
        })
        .select(:nonprofit_name, :gross_amount_cents, :net_amount_cents)
        .run

      # January donation: 10,000 cents ($100.00)
      expect(results.first[:gross_amount_cents]).to eq(10_000)
      # Net amount after refund: 5,000 cents ($50.00)
      expect(results.first[:net_amount_cents]).to eq(5_000)
    end
  end

  describe "column selection" do
    it "allows selecting only amount columns" do
      results = report_class
        .where(donation_status: { eq: "completed" })
        .select(:nonprofit_name, :gross_amount_cents, :refund_amount_cents, :net_amount_cents)
        .run

      # First nonprofit's total amounts
      whales = results.find { |r| r[:nonprofit_name] == "Save the Whales" }
      expect(whales).to include(
        gross_amount_cents: 30_000,   # $300.00
        refund_amount_cents: 5_000,   # $50.00
        net_amount_cents: 25_000      # $250.00
      )
    end
  end
end
