# Owner's Links editor payload: curated links (ordered, with spark + curation
# state) plus the user's other governed links available to add.
json.links @profile_links do |profile_link|
  json.partial! "api/v1/profiles/link", profile_link: profile_link, spark: @spark[profile_link.link_id]
end

json.available_links @available_links do |link|
  json.link_id link.id
  json.title link.title.presence || link.lookup_code
  json.slug link.lookup_code
  json.url link.original_url
  json.host link.host
  json.clicks link.clicks_count
  json.state link.state
end
