json.brand_page do
  json.(@brand_page, :content, :lookup_code, :published_at, :created_at, :updated_at)
end
