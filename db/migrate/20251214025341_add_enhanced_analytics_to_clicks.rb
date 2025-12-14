class AddEnhancedAnalyticsToClicks < ActiveRecord::Migration[7.2]
  def change
    # Geolocation fields (from CloudFront headers)
    add_column :clicks, :city, :string
    add_column :clicks, :region, :string
    add_column :clicks, :country_name, :string
    add_column :clicks, :postal_code, :string
    add_column :clicks, :latitude, :decimal, precision: 10, scale: 6
    add_column :clicks, :longitude, :decimal, precision: 10, scale: 6
    add_column :clicks, :timezone, :string

    # Device detection fields (from CloudFront headers + User-Agent parsing)
    add_column :clicks, :device_type, :string # 'mobile', 'desktop', 'tablet', 'smarttv', 'bot'
    add_column :clicks, :browser, :string
    add_column :clicks, :browser_version, :string
    add_column :clicks, :os, :string
    add_column :clicks, :os_version, :string

    # Device type flags (from CloudFront headers)
    add_column :clicks, :is_mobile, :boolean, default: false
    add_column :clicks, :is_tablet, :boolean, default: false
    add_column :clicks, :is_desktop, :boolean, default: false
    add_column :clicks, :is_bot, :boolean, default: false

    # Add indexes for common query patterns
    add_index :clicks, :city
    add_index :clicks, :region
    add_index :clicks, :country_name
    add_index :clicks, :device_type
    add_index :clicks, :is_mobile
    add_index :clicks, :is_bot
    add_index :clicks, [ :link_id, :created_at ], name: 'index_clicks_on_link_and_created'
    add_index :clicks, [ :device_type, :created_at ], name: 'index_clicks_on_device_and_created'
  end
end
