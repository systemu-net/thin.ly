class AddStripeIdToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :stripe_id, :string
  end
end
