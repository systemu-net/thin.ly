class CreateSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :subscriptions do |t|
      t.string :plan_id
      t.string :customer_id
      t.references :user, null: false, foreign_key: true
      t.string :status
      t.datetime :current_period_end
      t.datetime :current_period_start
      t.string :interval
      t.string :subscription_id

      t.timestamps
    end
  end
end
