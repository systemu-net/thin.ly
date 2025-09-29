json.brand_page do
  json.(@brand_page, :id, :content, :lookup_code, :published_at, :created_at, :updated_at)
  json.status @brand_page.status
  json.published_version_id @brand_page.published_version_id
  json.has_published_version @brand_page.draft? && @brand_page.published_version&.published?
  json.has_draft_version @brand_page.published? && @brand_page.draft_version.present?

  if @brand_page.draft? && @brand_page.published_version&.published?
    json.published_version do
      json.(@brand_page.published_version, :id, :lookup_code, :published_at)
    end
  end

  if @brand_page.published? && @brand_page.draft_version.present?
    json.draft_version do
      json.(@brand_page.draft_version, :id, :lookup_code, :updated_at)
    end
  end
end
