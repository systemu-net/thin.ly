json.user do
  json.call(
    resource, :id, :email, :created_at, :updated_at, :jti
  )
  json.avatar_url resource.avatar.url if resource.avatar.present?
end
