json.user do
  json.call(
    resource, :id, :email, :created_at, :updated_at, :jti
  )
end
