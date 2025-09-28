json.brand_pages @brand_pages do |brand_page|
  json.extract! brand_page, :content, :lookup_code, :published_at, :created_at, :updated_at
end
