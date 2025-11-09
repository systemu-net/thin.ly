class CreatePageViews < ActiveRecord::Migration[7.2]
  def change
    create_table :page_views do |t|
      t.references :brand_page, null: false, foreign_key: true
      t.string :ip_address
      t.text :user_agent
      t.string :referrer
      t.string :country
      t.string :city
      t.string :region
      t.string :browser
      t.string :browser_version
      t.string :os
      t.string :os_version
      t.string :device_type
      t.datetime :visited_at, null: false

      t.timestamps
    end

    add_index :page_views, :visited_at
    add_index :page_views, :country
    add_index :page_views, :device_type
    add_index :page_views, [ :brand_page_id, :visited_at ]
  end
end
