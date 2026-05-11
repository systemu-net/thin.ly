# Register JwtRememberMe to run immediately before Warden::JWTAuth::Middleware
# in the stack — which means it processes the *response* immediately *after*
# devise-jwt has written the Authorization header, giving us a chance to
# rewrite the JWT's exp claim when sign-in requested remember_me.
require "warden/jwt_auth/middleware"
require_relative "../../app/middleware/jwt_remember_me"

Rails.application.config.middleware.insert_before(
  Warden::JWTAuth::Middleware,
  JwtRememberMe
)
