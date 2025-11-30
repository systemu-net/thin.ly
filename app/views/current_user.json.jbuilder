json.call(
  current_user, :id, :email, :created_at, :updated_at, :jti
)
json.avatar_url current_user.avatar.url if current_user.avatar.present?
