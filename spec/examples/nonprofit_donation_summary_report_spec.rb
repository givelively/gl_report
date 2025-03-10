# frozen_string_literal: true

RSpec.describe "Example: NonprofitDonationSummaryReport" do
  before(:all) do
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    
    ActiveRecord::Schema.define do
      create_table :nonprofits do |t|
        t.string :name
        t.timestamps
      end

      create_table :donations do |t|
        t.references :nonprofit
        t.decimal :amount, precision: 10, scale: 2
        t.string :currency, default: "USD"
        t.string :status
        t.datetime :processed_at
        t.timestamps
      end

      create_table :refunds do |t|
        t.references :donation
        t.decimal :amount, precision: 10, scale: 2
        t.string :status
        t.timestamps
      end
    end

    class Nonprofit < ActiveRecord::Base
      has_many :donations
    end

    class Donation < ActiveRecord::Base
      belongs_to :nonprofit
      has_one :refund
    end

    class Refund < ActiveRecord::Base
      belongs_to :donation
    end
  end

  # ... cleanup code remains the same ...

  let(:report_class) do
    Class.new(GlReport::BaseReport) do
      model Nonprofit

      # Basic nonprofit information
      column :nonprofit_name,
        name: "Nonprofit Name",
        select: { name: "nonprofits.name" },
        value: ->(record, _) { record[:name] }

      # Filter columns (virtual)
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

      # Donation metrics
      column :total_donations,
        name: "Total Donations",
        select: { donation_count: "COUNT(DISTINCT donations.id)" },
        joins: :donations,
        value: ->(record, _) { record[:donation_count] }

      column :gross_amount,
        name: "Gross Amount",
        select: { gross: "COALESCE(SUM(donations.amount), 0)" },
        joins: :donations,
        value: ->(record, _) { BigDecimal(record[:gross].to_s) }

      # Refund metrics
      column :total_refunds,
        name: "Total Refunds",
        select: { refund_count: "COUNT(DISTINCT refunds.id)" },
        joins: { donations: :refund },
        value: ->(record, _) { record[:refund_count] }

      column :refund_amount,
        name: "Refund Amount",
        select: { refunds: "COALESCE(SUM(refunds.amount), 0)" },
        joins: { donations: :refund },
        value: ->(record, _) { BigDecimal(record[:refunds].to_s) }

      # Net amount calculation
      column :net_amount,
        name: "Net Amount",
        select: {
          donation_sum: "COALESCE(SUM(donations.amount), 0)",
          refund_sum: "COALESCE(SUM(refunds.amount), 0)"
        },
        joins: { donations: :refund },
        value: ->(record, _) { 
          BigDecimal(record[:donation_sum].to_s) - BigDecimal(record[:refund_sum].to_s)
        }
    end
  end

  let(:report) { report_class.new }

  # ... test data setup remains the same ...

  describe "column selection" do
    it "allows selecting only basic information" do
      results = report_class
        .where(donation_status: { eq: "completed" })
        .select(:nonprofit_name, :total_donations)
        .run

      expect(results.first.keys).to match_array([:nonprofit_name, :total_donations])
    end

    it "allows selecting financial metrics" do
      results = report_class
        .where(donation_status: { eq: "completed" })
        .select(:nonprofit_name, :gross_amount, :refund_amount, :net_amount)
        .run

      expect(results.first.keys).to match_array([
        :nonprofit_name,
        :gross_amount,
        :refund_amount,
        :net_amount
      ])
    end

    it "allows mixing and matching columns" do
      results = report_class
        .where(donation_status: { eq: "completed" })
        .select(:nonprofit_name, :total_donations, :net_amount)
        .run

      expect(results.first.keys).to match_array([
        :nonprofit_name,
        :total_donations,
        :net_amount
      ])
    end
  end

  describe "filtering" do
    it "filters by date range" do
      results = report_class
        .where(donation_status: { eq: "completed" })
        .where(donation_processed_at: { 
          gte: Time.utc(2025, 1, 1),
          lt: Time.utc(2025, 2, 1)
        })
        .select(:nonprofit_name, :gross_amount, :net_amount)
        .run

      expect(results.first[:gross_amount]).to eq(BigDecimal("100.00"))
    end
  end
end
