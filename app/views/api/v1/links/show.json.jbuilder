json.link do
  json.extract! @link, :lookup_code, :original_url, :title, :description, :created_at, :updated_at
  json.is_safe @link.is_safe
  json.clicks_count @link.clicks_count
  json.qr_codes @qr_codes do |qr_code|
    json.extract! qr_code, :image_url, :created_at, :updated_at
  end
  json.clicks @clicks do |click|
    json.extract! click, :id, :country, :ip_address, :referrer, :user_agent, :created_at, :updated_at
  end
end
