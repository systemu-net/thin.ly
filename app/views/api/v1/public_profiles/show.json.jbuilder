if @private
  # Placeholder for a private profile — minimal branded identity only.
  json.handle @profile.handle
  json.display_name @profile.display_name
  json.accent @profile.accent
  json.is_owner @is_owner
  json.private true
else
  json.partial! "api/v1/profiles/profile_core", profile: @profile
  json.is_owner @is_owner
  json.private false

  # Follower count is gated by the owner's show_followers privacy flag.
  json.followers_count(@profile.show_followers? ? @profile.followers_count : nil)

  json.links @profile_links do |profile_link|
    json.partial! "api/v1/profiles/link", profile_link: profile_link, spark: @spark[profile_link.link_id]
  end
end
