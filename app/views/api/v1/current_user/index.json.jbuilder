json.user do
  json.call(
    current_user, :id, :email, :created_at, :updated_at, :jti
  )
  json.role "admin"
  json.plan do
    json.name current_user.plan.name
    json.features @features
  end
end
