class AddProductToSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :subscriptions, :product, :string, null: false, default: "linkly"
    add_index :subscriptions, [ :user_id, :product ]
  end
end
