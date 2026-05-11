# When Users::SessionsController#respond_with sees a `remember_me` flag in the
# sign-in params, it sets ENV_FLAG on `request.env`. devise-jwt's downstream
# middleware then writes a 24-hour Authorization header. This middleware runs
# right after devise-jwt and rewrites the JWT's exp claim to 6 months so the
# session sticks until explicit sign-out (which still rotates user.jti and
# revokes both short- and long-lived tokens).
class JwtRememberMe
  ENV_FLAG = "jwt_remember_me.extend".freeze
  REMEMBER_ME_EXPIRATION = 6.months.to_i

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    return [ status, headers, body ] unless env[ENV_FLAG]

    auth = headers["Authorization"]
    return [ status, headers, body ] unless auth&.start_with?("Bearer ")

    token = auth.split(" ", 2).last
    payload = JWT.decode(token, jwt_secret, true, algorithm: "HS256").first
    payload["exp"] = Time.current.to_i + REMEMBER_ME_EXPIRATION
    headers["Authorization"] = "Bearer #{JWT.encode(payload, jwt_secret, "HS256")}"

    [ status, headers, body ]
  rescue JWT::DecodeError => e
    Rails.logger.warn "JwtRememberMe failed to extend token: #{e.message}"
    [ status, headers, body ]
  end

  private

  def jwt_secret
    ENV["SECRET_KEY_BASE"] || Rails.application.credentials.fetch(:secret_key_base)
  end
end
