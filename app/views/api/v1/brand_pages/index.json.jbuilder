json.brand_pages @brand_pages do |brand_page|
  json.extract! brand_page, :id, :content, :lookup_code, :title, :description, :published_at, :created_at, :updated_at
  json.status brand_page.status
  json.published_lookup_code brand_page.published_version.lookup_code if brand_page.published_version&.published?
  json.has_published_version brand_page.draft? && brand_page.published_version&.published?
  json.has_draft_version brand_page.published? && brand_page.draft_version.present?
end
