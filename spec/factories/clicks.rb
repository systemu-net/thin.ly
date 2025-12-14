# == Schema Information
#
# Table name: clicks
#
#  id              :bigint           not null, primary key
#  browser         :string
#  browser_version :string
#  city            :string
#  country         :string
#  country_name    :string
#  device_type     :string
#  ip_address      :string
#  is_bot          :boolean          default(FALSE)
#  is_desktop      :boolean          default(FALSE)
#  is_mobile       :boolean          default(FALSE)
#  is_tablet       :boolean          default(FALSE)
#  latitude        :decimal(10, 6)
#  longitude       :decimal(10, 6)
#  os              :string
#  os_version      :string
#  postal_code     :string
#  referrer        :string
#  region          :string
#  source          :string
#  timezone        :string
#  user_agent      :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  link_id         :bigint           not null
#
# Indexes
#
#  index_clicks_on_city                (city)
#  index_clicks_on_country_name        (country_name)
#  index_clicks_on_device_and_created  (device_type,created_at)
#  index_clicks_on_device_type         (device_type)
#  index_clicks_on_is_bot              (is_bot)
#  index_clicks_on_is_mobile           (is_mobile)
#  index_clicks_on_link_and_created    (link_id,created_at)
#  index_clicks_on_link_id             (link_id)
#  index_clicks_on_region              (region)
#  index_clicks_on_source              (source)
#
# Foreign Keys
#
#  fk_rails_...  (link_id => links.id)
#
FactoryBot.define do
  factory :click do
    link { nil }
  end
end
