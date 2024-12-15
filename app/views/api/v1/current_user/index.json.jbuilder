json.user do
  json.call(
    current_user, :id, :email, :created_at, :updated_at, :jti
  )
  json.role "admin"
end
