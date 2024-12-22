json.links @links do |link|
  json.extract! link, :lookup_code, :original_url, :created_at, :updated_at
  json.has_qr_codes link.qr_codes.any?
end
