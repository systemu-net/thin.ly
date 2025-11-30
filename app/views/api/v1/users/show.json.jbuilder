json.id @user.id
json.email @user.email
json.created_at @user.created_at
json.updated_at @user.updated_at
json.jti @user.jti
json.avatar_url @user.avatar.url if @user.avatar.present?
