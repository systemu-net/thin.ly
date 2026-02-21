class AddSubscriptionManagementFields < ActiveRecord::Migration[7.2]
  def change
    add_column :subscriptions, :cancel_at_period_end, :boolean, default: false, null: false
    add_column :subscriptions, :stripe_price_id, :string
  end
end
