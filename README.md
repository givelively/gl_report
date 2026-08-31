# gl_report

A flexible, SQL-optimized reporting DSL for Ruby on Rails and ActiveRecord applications with support for joins, aggregated columns, virtual formatting, and SQL/in-memory filtering.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'gl_report'
```

And then execute:

```bash
bundle install
```

## Features

- **SQL Optimization**: Automatically builds queries with required `SELECT` aliases, `LEFT OUTER JOIN`s, and `GROUP BY` grouping.
- **Dual-Mode Filtering**: Filters are pushed to SQL where possible; virtual or computed columns are evaluated in-memory.
- **Column Selection**: Select only the columns you need with `.select(...)`.
- **Enumerable Support**: Chain or iterate directly over filtered report relations (`each`, `map`, `first`, `count`).
- **Flexible Values**: Support custom value computation procs or default attribute mapping.

## Usage

### 1. Define a Report Class

Inherit from `GlReport::BaseReport` and declare the model, joins, and columns:

```ruby
class DonationReport < GlReport::BaseReport
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
         select_only: true,
         value: ->(record, report) { report.format_currency(record[:amount], record[:currency]) }

  column :status,
         name: 'Status',
         select: { status: 'donations.status' },
         value: ->(record, _) { record[:status]&.titleize }

  def format_currency(amount, currency)
    "#{currency} #{format('%.2f', amount)}"
  end
end
```

### 2. Run and Filter Reports

```ruby
# Query from the class
results = DonationReport
  .where(status: { eq: 'completed' })
  .where(amount: { gte: 50.00 })
  .select(:donor_name, :formatted_amount)
  .run

# Or instantiate with a pre-existing scope
scoped_report = DonationReport.new(scope: Donation.where(campaign_id: 123))
results = scoped_report
  .where(status: { in: ['completed', 'pending'] })
  .run
```

### 3. Filter Operators

Supported operators for both SQL and in-memory evaluation:

| Operator | SQL Equivalent | In-Memory Behavior |
| :--- | :--- | :--- |
| `eq` | `=` or `IS NULL` | `==` |
| `ne` / `not_eq` | `!=` or `IS NOT NULL` | `!=` |
| `gt` | `>` | `>` |
| `gte` | `>=` | `>=` |
| `lt` | `<` | `<` |
| `lte` | `<=` | `<=` |
| `like` | `LIKE %val%` | Case-sensitive substring `include?` |
| `ilike` | `ILIKE %val%` | Case-insensitive substring match |
| `in` | `IN (...)` | `Array#include?` |
| `not_in` | `NOT IN (...)` | `!Array#include?` |

## Development

After checking out the repo, run:

```bash
bin/setup # or bundle install
bundle exec rspec
bundle exec rubocop
```

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).
