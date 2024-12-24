json.qr_codes @qr_codes do |qr_code|
  json.extract! qr_code, :image_url, :created_at, :updated_at, :link_id
end
