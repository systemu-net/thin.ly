class CreateProcessedStripeEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :processed_stripe_events do |t|
      t.string :stripe_event_id, null: false, index: { unique: true }
      t.string :event_type, null: false
      t.datetime :processed_at, null: false

      t.timestamps
    end

    add_index :processed_stripe_events, :event_type
    add_index :processed_stripe_events, :processed_at
  end
end
