json.user do
  json.call(
    current_user, :id, :email, :created_at, :updated_at, :jti
  )
  json.avatar_url current_user.avatar.url if current_user.avatar.present?
  json.handle current_user.profile&.handle
  json.role "admin"
  json.plan do
    json.name current_user.plan.name
    json.features @features
  end
end
