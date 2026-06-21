# A curated link row. Shared by the public profile view and the owner's Links
# editor. `spark` is an optional [Int] daily-clicks series (7d) passed by the
# consuming view; `link` is the underlying governed Link.
link = profile_link.link

json.id profile_link.id
json.link_id link.id
json.title profile_link.display_title
json.title_override profile_link.title_override
json.slug link.lookup_code
json.url link.original_url
json.host link.host
json.clicks link.clicks_count
json.state link.state
json.tag profile_link.tag
json.pinned profile_link.pinned
json.visible profile_link.visible
json.position profile_link.position
json.spark(defined?(spark) ? (spark || []) : [])
