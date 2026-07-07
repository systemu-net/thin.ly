# frozen_string_literal: true

module Levelcode
  # Mints, verifies and revokes the **editor access/refresh tokens** used by the
  # LevelCode editor to talk to `/api/levelcode/v1/*` (SPEC §2).
  #
  # These are distinct from the browser (devise-jwt) tokens: they are signed with
  # LEVELCODE_JWT_SECRET, HS256, and carry an explicit scope. Revocation is a `jti`
  # denylist held in a Redis set (`levelcode:revoked:jti`).
  #
  #   access  — TTL 60 min, scope "ai:chat account:read"
  #   refresh — TTL 30 days, scope "refresh"
  module EditorToken
    module_function

    ALGORITHM      = "HS256"
    ACCESS_TTL     = 60.minutes
    REFRESH_TTL    = 30.days
    # ai:chat  — plain completions through the gateway
    # ai:agent — tool-calling (agent) turns; same endpoint, distinct scope so a
    #            reduced-capability token can be issued and so agent use is
    #            explicit. (Per-USER agent access is a PLAN entitlement, enforced
    #            in the gateway — not the token scope.)
    # account:read — profile/usage/billing reads.
    ACCESS_SCOPE   = "ai:chat ai:agent account:read"
    REFRESH_SCOPE  = "refresh"
    SESSION_TTL    = 30.days
    SESSION_SCOPE  = "account:read" # web session: account/billing reads only, NOT the AI gateway
    REVOKED_SET    = "levelcode:revoked:jti"

    class Error < StandardError; end
    class InvalidToken < Error; end

    # Mint a short-lived access token for the user.
    def mint_access(user)
      encode(user, scope: ACCESS_SCOPE, ttl: ACCESS_TTL)
    end

    # Mint a long-lived refresh token for silent renewal.
    def mint_refresh(user)
      encode(user, scope: REFRESH_SCOPE, ttl: REFRESH_TTL)
    end

    # Mint the WEB session token (levelcode.ai httpOnly cookie). Long-lived to match
    # the cookie, and scoped to account reads only — it must NOT be usable at the
    # AI gateway (carries no ai:* scope).
    def mint_session(user)
      encode(user, scope: SESSION_SCOPE, ttl: SESSION_TTL)
    end

    # Verify signature + expiry, then (optionally) assert the scope and that the
    # jti has not been revoked. Returns the decoded claims hash, or raises
    # InvalidToken.
    def verify(token, scope: nil)
      claims, = JWT.decode(token.to_s, secret, true, algorithm: ALGORITHM)

      if scope && !scopes_for(claims).include?(scope)
        raise InvalidToken, "token missing required scope: #{scope}"
      end
      raise InvalidToken, "token revoked" if revoked?(claims["jti"])

      claims
    rescue JWT::DecodeError => e
      raise InvalidToken, e.message
    end

    # Add a jti to the Redis denylist so future verifications reject it. Kept for
    # the token's remaining lifetime; we set a generous TTL matching the longest
    # (refresh) token so the entry self-expires.
    def revoke!(jti)
      return false if jti.blank?
      return false unless redis

      redis.sadd(REVOKED_SET, jti)
      redis.expire(REVOKED_SET, REFRESH_TTL.to_i)
      true
    end

    def revoked?(jti)
      return false if jti.blank?
      return false unless redis

      redis.sismember(REVOKED_SET, jti)
    rescue StandardError => e
      # Fail-open on Redis trouble — a signed, unexpired token still authenticates.
      Rails.logger.warn("Levelcode::EditorToken revoked? check failed: #{e.message}")
      false
    end

    # --- internals -----------------------------------------------------------

    def encode(user, scope:, ttl:)
      now = Time.now.to_i
      payload = {
        sub: user.id,
        jti: SecureRandom.uuid,
        scope: scope,
        iat: now,
        exp: now + ttl.to_i
      }
      JWT.encode(payload, secret, ALGORITHM)
    end

    def scopes_for(claims)
      claims["scope"].to_s.split(/\s+/)
    end

    def redis
      defined?($redis) ? $redis : nil
    end

    def secret
      ENV["LEVELCODE_JWT_SECRET"].presence ||
        Rails.application.credentials.dig(:levelcode_jwt_secret) ||
        raise(Error, "LEVELCODE_JWT_SECRET is not configured")
    end
    private_class_method :encode, :scopes_for, :redis, :secret
  end
end
