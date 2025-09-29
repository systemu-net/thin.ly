json.brand_pages @brand_pages do |brand_page|
  json.extract! brand_page, :id, :content, :lookup_code, :published_at, :created_at, :updated_at
  json.status brand_page.status
  json.published_version_id brand_page.published_version_id
  json.has_published_version brand_page.draft? && brand_page.published_version&.published?
  json.has_draft_version brand_page.published? && brand_page.draft_version.present?
end
