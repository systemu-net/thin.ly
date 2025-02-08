class CreatePlans < ActiveRecord::Migration[7.2]
  def change
    create_table :plans do |t|
      t.references :subscription, null: false, foreign_key: true
      t.integer :links
      t.integer :qr_codes
      t.integer :pages

      t.timestamps
    end
  end
end
