json.links @links do |link|
  json.extract! link, :lookup_code, :original_url, :title, :description, :created_at, :updated_at
  json.clicks_count link.clicks_count
  json.is_safe link.is_safe
  json.routing_rules_count link.routing_rules.size
  json.partial! "governance_fields", link: link
end

json.pagination do
  json.count    @pagination[:count]
  json.page     @pagination[:page]
  json.limit    @pagination[:limit]
  json.pages    @pagination[:pages]
  json.next     @pagination[:next]
  json.prev     @pagination[:prev]
end

json.stats do
  json.total        @stats[:total]
  json.active       @stats[:active]
  json.paused       @stats[:paused]
  json.total_clicks @stats[:total_clicks]
end
