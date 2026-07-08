class CreateUsageFeedbacks < ActiveRecord::Migration[7.2]
  def change
    create_table :usage_feedbacks do |t|
      t.references :user, null: false, foreign_key: true

      t.string :model                     # the model that produced the reacted-to turn
      t.string :rating, null: false        # "up" | "down"
      t.string :request_id                 # optional link to a usage_event (future per-request linkage)

      # Append-only signal rows — only created_at is meaningful.
      t.datetime :created_at, null: false
    end

    add_index :usage_feedbacks, [ :user_id, :created_at ]
  end
end
