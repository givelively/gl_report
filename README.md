# gl_report
A flexible reporting DSL

## Example

### Define the Models
Assume we have `User` and `Order` models in our application. Each user can have multiple orders.

```ruby
class User < ApplicationRecord
  # Example attributes: id, name, email, created_at, updated_at
  has_many :orders
end
```

```ruby
class Order < ApplicationRecord
  # Example attributes: id, user_id, total_price, status, created_at, updated_at
  belongs_to :user
end
```

### Create a Report Class
Create a report class that inherits from `GlReport::BaseReport`.
This class will define the structure and content of the report.

```ruby
module Reports
  class OrderReport < GlReport::BaseReport
    # Define the model this report is based on
    model Order

    # Define columns for the report
    column :order_id, sql_fragment: "orders.id", filterable: true, sortable: true
    column :total_price, sql_fragment: "orders.total_price", filterable: true, sortable: true
    column :order_status, sql_fragment: "orders.status", filterable: true
    column :order_created_at, sql_fragment: "orders.created_at", filterable: true, sortable: true

    # Define joins for related models
    joins do |query|
      query.joins(:user)
    end
    
    # Define columns for the joined user model
    column :user_name, sql_fragment: "users.name", filterable: true
    column :user_email, sql_fragment: "users.email", filterable: true
    column :user_created_at, sql_fragment: "users.created_at", filterable: true
  end
end

# Using the report
report = Reports::OrderReport.new
report = report.where(
  order_status: { eq: 'completed' },
  total_price: { gt: 100.0 }
)
results = report.run
```
