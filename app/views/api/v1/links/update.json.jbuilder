json.link do
  json.(@link, :lookup_code, :title, :description, :created_at, :updated_at)
  json.is_safe @link.is_safe
  json.clicks_count @link.clicks_count
end
