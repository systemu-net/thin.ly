# spec/support/auth_helpers.rb
module AuthHelpers
  def auth_headers(user)
    token = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
    { 'Authorization' => "Bearer #{token}" }
  end
end
