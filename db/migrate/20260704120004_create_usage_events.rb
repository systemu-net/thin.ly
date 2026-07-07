class CreateUsageEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :usage_events do |t|
      t.references :user, null: false, foreign_key: true

      t.string :request_id
      t.string :model
      t.string :provider

      # Token accounting (bigint) + computed cost in micro-dollars.
      t.bigint :input_tokens,        null: false, default: 0
      t.bigint :output_tokens,       null: false, default: 0
      t.bigint :cached_input_tokens, null: false, default: 0
      t.bigint :cost_micros,         null: false, default: 0

      # Durable ledger rows are append-only; only created_at is meaningful.
      t.datetime :created_at, null: false
    end

    add_index :usage_events, [ :user_id, :created_at ]
  end
end
