# Owner view of their own profile — full, including private/owner-only fields.
json.partial! "api/v1/profiles/profile_core", profile: @profile

json.is_owner true

json.privacy do
  Profile::PRIVACY_KEYS.each { |flag| json.set! flag, @profile.public_send("#{flag}?") }
end

json.published_at @profile.published_at
json.followers_count @profile.followers_count
json.following_count @profile.following_count
