json.qr_codes @qr_codes do |qr_code|
  json.extract! qr_code, :id, :image_url, :created_at, :updated_at

  if qr_code.link
    json.link do
      json.extract! qr_code.link, :lookup_code, :original_url, :title, :description
      json.scans_count qr_code.scans_count
    end
  end
end
