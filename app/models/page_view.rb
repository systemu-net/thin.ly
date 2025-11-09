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
class PageView < ApplicationRecord
  belongs_to :brand_page

  validates :visited_at, presence: true
  validates :brand_page, presence: true

  # Scopes for analytics
  scope :recent, -> { order(visited_at: :desc) }
  scope :today, -> { where("visited_at >= ?", Time.current.beginning_of_day) }
  scope :this_week, -> { where("visited_at >= ?", Time.current.beginning_of_week) }
  scope :this_month, -> { where("visited_at >= ?", Time.current.beginning_of_month) }
  scope :by_country, ->(country) { where(country: country) }
  scope :by_device, ->(device_type) { where(device_type: device_type) }

  # Class method to create from request data
  def self.track_view(brand_page, request_data)
    create(
      brand_page: brand_page,
      ip_address: request_data[:ip_address],
      user_agent: request_data[:user_agent],
      referrer: request_data[:referrer],
      country: request_data[:country],
      city: request_data[:city],
      region: request_data[:region],
      browser: request_data[:browser],
      browser_version: request_data[:browser_version],
      os: request_data[:os],
      os_version: request_data[:os_version],
      device_type: request_data[:device_type],
      visited_at: request_data[:visited_at] || Time.current
    )
  end
end
