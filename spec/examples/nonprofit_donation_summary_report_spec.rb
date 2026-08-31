# frozen_string_literal: true

module NonprofitReportExample
  class Nonprofit < ActiveRecord::Base
    self.table_name = 'nonprofits'
    has_many :donations, class_name: 'NonprofitReportExample::Donation', foreign_key: 'nonprofit_id'
  end

  class Donation < ActiveRecord::Base
    self.table_name = 'donations'
    belongs_to :nonprofit, class_name: 'NonprofitReportExample::Nonprofit', foreign_key: 'nonprofit_id'
    has_one :refund, class_name: 'NonprofitReportExample::Refund', foreign_key: 'donation_id'
  end

  class Refund < ActiveRecord::Base
    self.table_name = 'refunds'
    belongs_to :donation, class_name: 'NonprofitReportExample::Donation', foreign_key: 'donation_id'
  end
end

RSpec.describe 'Example: NonprofitDonationSummaryReport' do
  before(:all) do
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')

    ActiveRecord::Schema.define do
      create_table :nonprofits, force: true do |t|
        t.string :name
        t.timestamps
      end

      create_table :donations, force: true do |t|
        t.references :nonprofit
        t.integer :amount_cents, null: false
        t.string :currency, default: 'USD'
        t.string :status
        t.datetime :processed_at
        t.timestamps
      end

      create_table :refunds, force: true do |t|
        t.references :donation
        t.integer :amount_cents, null: false
        t.string :status
        t.timestamps
      end
    end
  end

  after(:all) do
    ActiveRecord::Base.connection.drop_table(:refunds) if ActiveRecord::Base.connection.table_exists?(:refunds)
    ActiveRecord::Base.connection.drop_table(:donations) if ActiveRecord::Base.connection.table_exists?(:donations)
    ActiveRecord::Base.connection.drop_table(:nonprofits) if ActiveRecord::Base.connection.table_exists?(:nonprofits)
  end

  before do
    NonprofitReportExample::Refund.destroy_all
    NonprofitReportExample::Donation.destroy_all
    NonprofitReportExample::Nonprofit.destroy_all
  end

  let(:report_class) do
    Class.new(GlReport::BaseReport) do
      model NonprofitReportExample::Nonprofit

      column :nonprofit_name,
             name: 'Nonprofit Name',
             select: { name: 'nonprofits.name' },
             value: ->(record, _) { record[:name] }

      column :donation_processed_at,
             name: 'Donation Date',
             select: { processed_at: 'donations.processed_at' },
             joins: :donations,
             value: ->(record, _) { record[:processed_at] }

      column :donation_status,
             name: 'Status',
             select: { status: 'donations.status' },
             joins: :donations,
             value: ->(record, _) { record[:status] }

      column :total_donations,
             name: 'Total Donations',
             select: { donation_count: 'COUNT(DISTINCT donations.id)' },
             joins: :donations,
             value: ->(record, _) { record[:donation_count] }

      column :gross_amount_cents,
             name: 'Gross Amount (cents)',
             select: { gross_cents: 'COALESCE(SUM(donations.amount_cents), 0)' },
             joins: :donations,
             value: ->(record, _) { record[:gross_cents] }

      column :refund_amount_cents,
             name: 'Refund Amount (cents)',
             select: { refunds_cents: 'COALESCE(SUM(refunds.amount_cents), 0)' },
             joins: { donations: :refund },
             value: ->(record, _) { record[:refunds_cents] }

      column :net_amount_cents,
             name: 'Net Amount (cents)',
             select: {
               donation_sum_cents: 'COALESCE(SUM(donations.amount_cents), 0)',
               refund_sum_cents: 'COALESCE(SUM(refunds.amount_cents), 0)'
             },
             joins: { donations: :refund },
             value: ->(record, _) { record[:donation_sum_cents] - record[:refund_sum_cents] }
    end
  end

  let!(:nonprofit1) { NonprofitReportExample::Nonprofit.create!(name: 'Save the Whales') }
  let!(:nonprofit2) { NonprofitReportExample::Nonprofit.create!(name: 'Plant Trees') }

  let!(:donation1) do
    NonprofitReportExample::Donation.create!(
      nonprofit: nonprofit1,
      amount_cents: 10_000,
      status: 'completed',
      processed_at: Time.utc(2025, 1, 15)
    )
  end

  let!(:donation2) do
    NonprofitReportExample::Donation.create!(
      nonprofit: nonprofit1,
      amount_cents: 20_000,
      status: 'completed',
      processed_at: Time.utc(2025, 2, 20)
    )
  end

  let!(:donation3) do
    NonprofitReportExample::Donation.create!(
      nonprofit: nonprofit2,
      amount_cents: 15_000,
      status: 'completed',
      processed_at: Time.utc(2025, 1, 1)
    )
  end

  let!(:refund1) do
    NonprofitReportExample::Refund.create!(
      donation: donation1,
      amount_cents: 5_000,
      status: 'completed'
    )
  end

  describe 'filtering' do
    it 'filters by date range' do
      results = report_class
                .where(donation_status: { eq: 'completed' })
                .where(donation_processed_at: {
                         gte: Time.utc(2025, 1, 1),
                         lt: Time.utc(2025, 2, 1)
                       })
                .select(:nonprofit_name, :gross_amount_cents, :net_amount_cents)
                .run

      whales = results.find { |r| r[:nonprofit_name] == 'Save the Whales' }
      expect(whales[:gross_amount_cents]).to eq(10_000)
      expect(whales[:net_amount_cents]).to eq(5_000)
    end
  end

  describe 'column selection' do
    it 'allows selecting only amount columns' do
      results = report_class
                .where(donation_status: { eq: 'completed' })
                .select(:nonprofit_name, :gross_amount_cents, :refund_amount_cents, :net_amount_cents)
                .run

      whales = results.find { |r| r[:nonprofit_name] == 'Save the Whales' }
      expect(whales).to include(
        gross_amount_cents: 30_000,
        refund_amount_cents: 5_000,
        net_amount_cents: 25_000
      )
    end
  end
end
