json.links @links do |link|
  json.extract! link, :lookup_code, :original_url, :title, :description, :created_at, :updated_at
  json.clicks_count link.clicks_count
  json.is_safe link.is_safe
end
