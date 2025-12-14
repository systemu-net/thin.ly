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
class Click < ApplicationRecord
  belongs_to :link, counter_cache: true

  # Scopes for device type filtering
  scope :mobile, -> { where(is_mobile: true) }
  scope :desktop, -> { where(is_desktop: true) }
  scope :tablet, -> { where(is_tablet: true) }
  scope :bots, -> { where(is_bot: true) }
  scope :human_traffic, -> { where(is_bot: false) }

  # Scopes for source filtering
  scope :qr_scans, -> { where(source: "qr") }
  scope :direct_clicks, -> { where(source: nil) }

  # Scopes for geographic filtering
  scope :by_country, ->(country) { where(country_name: country) }
  scope :by_city, ->(city) { where(city: city) }
  scope :by_region, ->(region) { where(region: region) }

  # Scopes for device type filtering (by device_type string)
  scope :by_device_type, ->(type) { where(device_type: type) }

  # Scope for time-based queries
  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where(created_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :this_week, -> { where(created_at: Time.current.beginning_of_week..Time.current.end_of_week) }
  scope :this_month, -> { where(created_at: Time.current.beginning_of_month..Time.current.end_of_month) }

  after_create :increment_qr_code_scans_count, if: :qr_scan?
  after_destroy :decrement_qr_code_scans_count, if: :qr_scan?

  # Instance methods
  def qr_scan?
    source == "qr"
  end

  def mobile_device?
    is_mobile || is_tablet
  end

  def location
    return nil unless latitude.present? && longitude.present?

    {
      latitude: latitude.to_f,
      longitude: longitude.to_f,
      city: city,
      region: region,
      country: country_name,
      postal_code: postal_code,
      timezone: timezone
    }
  end

  private

  def increment_qr_code_scans_count
    qr_code = link.qr_codes.find_by(user_id: link.user_id)
    qr_code&.increment!(:scans_count)
  end

  def decrement_qr_code_scans_count
    qr_code = link.qr_codes.find_by(user_id: link.user_id)
    qr_code&.decrement!(:scans_count)
  end
end
