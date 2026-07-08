class CreateCreditWallets < ActiveRecord::Migration[7.2]
  def change
    create_table :credit_wallets do |t|
      t.references :user, null: false, foreign_key: true

      # Product scope (levelcode gateway credits are separate from the link product).
      t.string :product,  null: false, default: "levelcode"
      t.string :plan_key, null: false

      # Per-period token caps and running usage (bigint — token counts get large).
      t.bigint :input_cap,   null: false
      t.bigint :output_cap,  null: false
      t.bigint :input_used,  null: false, default: 0
      t.bigint :output_used, null: false, default: 0

      # Billing period window this wallet meters against.
      t.datetime :period_start
      t.datetime :period_end

      # What happens once a cap is hit: throttle (default) | topup | stop.
      t.string :overage_policy, null: false, default: "throttle"

      t.timestamps
    end

    # One wallet per user per product.
    add_index :credit_wallets, [ :user_id, :product ], unique: true
  end
end
