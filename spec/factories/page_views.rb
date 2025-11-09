# == Schema Information
#
# Table name: page_views
#
#  id              :bigint           not null, primary key
#  browser         :string
#  browser_version :string
#  city            :string
#  country         :string
#  device_type     :string
#  ip_address      :string
#  os              :string
#  os_version      :string
#  referrer        :string
#  region          :string
#  user_agent      :text
#  visited_at      :datetime         not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  brand_page_id   :bigint           not null
#
# Indexes
#
#  index_page_views_on_brand_page_id                 (brand_page_id)
#  index_page_views_on_brand_page_id_and_visited_at  (brand_page_id,visited_at)
#  index_page_views_on_country                       (country)
#  index_page_views_on_device_type                   (device_type)
#  index_page_views_on_visited_at                    (visited_at)
#
# Foreign Keys
#
#  fk_rails_...  (brand_page_id => brand_pages.id)
#
FactoryBot.define do
  factory :page_view do
    association :brand_page
    ip_address { "192.168.1.1" }
    user_agent { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36" }
    referrer { "https://www.google.com" }
    country { "US" }
    city { "New York" }
    region { "NY" }
    browser { "Chrome" }
    browser_version { "141.0.0.0" }
    os { "macOS" }
    os_version { "10.15.7" }
    device_type { "desktop" }
    visited_at { Time.current }

    trait :mobile do
      user_agent { "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15" }
      device_type { "mobile" }
      os { "iOS" }
      os_version { "15.0" }
      browser { "Safari" }
    end

    trait :tablet do
      user_agent { "Mozilla/5.0 (iPad; CPU OS 15_0 like Mac OS X) AppleWebKit/605.1.15" }
      device_type { "tablet" }
      os { "iOS" }
      os_version { "15.0" }
    end
  end
end
