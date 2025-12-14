json.link do
  json.extract! @link, :lookup_code, :original_url, :title, :description, :created_at, :updated_at
  json.is_safe @link.is_safe
  json.clicks_count @link.clicks_count
  json.qr_codes @qr_codes do |qr_code|
    json.extract! qr_code, :image_url, :created_at, :updated_at
  end
  json.clicks @clicks do |click|
    json.extract! click, :id, :country, :ip_address, :referrer, :user_agent, :created_at, :updated_at

    # Enhanced analytics data
    json.city click.city
    json.region click.region
    json.country_name click.country_name
    json.postal_code click.postal_code
    json.latitude click.latitude
    json.longitude click.longitude
    json.timezone click.timezone
    json.device_type click.device_type
    json.browser click.browser
    json.browser_version click.browser_version
    json.os click.os
    json.os_version click.os_version
    json.is_mobile click.is_mobile
    json.is_tablet click.is_tablet
    json.is_desktop click.is_desktop
    json.is_bot click.is_bot
    json.source click.source
  end
end
