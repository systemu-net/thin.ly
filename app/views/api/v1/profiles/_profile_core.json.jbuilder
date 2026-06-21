# Always-public identity fields for a profile. Shared by the owner endpoint
# (profiles#show) and the public-by-handle endpoint. Privacy-gated fields
# (privacy object, followers, draft state) are added by the consuming view.
json.id profile.id
json.handle profile.handle
json.display_name profile.display_name
json.bio profile.bio
json.location profile.location
json.website profile.website
json.accent profile.accent
json.verified profile.verified_badge?
json.socials profile.socials
json.avatar_url(profile.user.avatar.present? ? profile.user.avatar.url : nil)
json.public_url profile.public_url
json.published profile.published?
json.created_at profile.created_at
json.updated_at profile.updated_at
