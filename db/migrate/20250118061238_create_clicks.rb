class CreateClicks < ActiveRecord::Migration[7.2]
  def change
    create_table :clicks do |t|
      t.references :link, null: false, foreign_key: true

      t.string :ip_address
      t.string :user_agent
      t.string :referrer
      t.string :country
      t.timestamps
    end
  end
end
