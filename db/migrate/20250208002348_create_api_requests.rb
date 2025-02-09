class CreateApiRequests < ActiveRecord::Migration[7.2]
  def change
    create_table :api_requests do |t|
      t.references :plan, null: false, foreign_key: true
      t.references :logable, polymorphic: true, null: false

      t.timestamps
    end
  end
end
