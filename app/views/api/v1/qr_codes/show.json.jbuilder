json.qr_code do
  json.extract! @qr_code, :id, :image_url, :created_at, :updated_at, :link_id
end
