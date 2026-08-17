require 'active_record'

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Schema.define do
  create_table :nonprofits do |t|
    t.string :name
  end

  create_table :donations do |t|
    t.references :nonprofit
    t.integer :amount_cents, null: false
    t.string :status
    t.datetime :processed_at
  end

  create_table :refunds do |t|
    t.references :donation
    t.integer :amount_cents, null: false
    t.string :status
  end
end

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

n1 = Nonprofit.create!(name: "Save the Whales")
n2 = Nonprofit.create!(name: "Plant Trees")

d1 = Donation.create!(nonprofit: n1, amount_cents: 10_000, status: "completed", processed_at: Time.utc(2025, 1, 15))
d2 = Donation.create!(nonprofit: n1, amount_cents: 20_000, status: "completed", processed_at: Time.utc(2025, 2, 20))
d3 = Donation.create!(nonprofit: n2, amount_cents: 15_000, status: "completed", processed_at: Time.utc(2025, 1, 1))

r1 = Refund.create!(donation: d1, amount_cents: 5_000, status: "completed")

query = Nonprofit.left_outer_joins(donations: :refund)
  .select("nonprofits.id AS id")
  .select("nonprofits.name AS nonprofit_name")
  .select("donations.processed_at AS donation_processed_at")
  .select("donations.status AS donation_status")
  .select("COALESCE(SUM(donations.amount_cents), 0) AS gross_cents")
  .select("COALESCE(SUM(refunds.amount_cents), 0) AS refunds_cents")

puts "WITHOUT GROUP BY:"
query.to_a.each do |record|
  puts "#{record.id} | #{record[:nonprofit_name]} | #{record[:gross_cents]} | #{record[:refunds_cents]}"
end

query = query.group("nonprofits.id")
puts "\nWITH GROUP BY:"
query.to_a.each do |record|
  puts "#{record.id} | #{record[:nonprofit_name]} | #{record[:gross_cents]} | #{record[:refunds_cents]}"
end
