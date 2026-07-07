# frozen_string_literal: true

module Levelcode
  # Single-use, short-lived authorization codes for the hardened editor sign-in
  # flow (SPEC §2.1, M-G6). The site 302s the editor to
  # `<callback>?code=<one_time_code>`; the editor then POSTs `{code, verifier}`
  # to `/api/levelcode/v1/auth/exchange`, which redeems the code and mints tokens.
  #
  # PKCE (S256): at issue time we store the user id plus the caller-supplied
  # `code_challenge`. At redeem time the caller must present the matching
  # `code_verifier` (SHA256 → base64url == stored challenge). The code is deleted
  # on the first redemption attempt, so it can never be replayed.
  module OneTimeCode
    module_function

    TTL          = 60.seconds
    KEY_PREFIX   = "levelcode:otc:"

    class Error < StandardError; end
    class InvalidCode < Error; end
    class InvalidVerifier < Error; end

    # Issue a code bound to the user, optionally to a PKCE challenge. Returns the
    # opaque code. When `pkce_challenge` is blank the code is unbound (still
    # single-use + 60s TTL + delivered only over the editor's custom URI scheme);
    # PKCE binding is a hardening enabled once the editor challenge is threaded
    # through the site (DECISIONS D15).
    def issue(user, pkce_challenge = nil)
      raise Error, "redis unavailable" unless redis

      code = SecureRandom.urlsafe_base64(32)
      payload = { "user_id" => user.id, "challenge" => pkce_challenge.to_s.presence }
      redis.setex(key(code), TTL.to_i, payload.to_json)
      code
    end

    # Redeem a code, verifying the PKCE verifier IFF the code was issued with a
    # challenge. Single-use: the code is deleted before verification so a failed
    # attempt cannot be retried. Returns the User or raises InvalidCode /
    # InvalidVerifier.
    def redeem(code, verifier = nil)
      raise InvalidCode, "missing code" if code.blank?
      raise Error, "redis unavailable" unless redis

      raw = redis.getdel(key(code))
      raise InvalidCode, "unknown or expired code" if raw.blank?

      data = JSON.parse(raw)
      challenge = data["challenge"]
      if challenge.present? && !pkce_matches?(challenge, verifier)
        raise InvalidVerifier, "PKCE verifier mismatch"
      end

      user = User.find_by(id: data["user_id"])
      raise InvalidCode, "user no longer exists" unless user

      user
    end

    # --- internals -----------------------------------------------------------

    # S256: BASE64URL-NO-PAD( SHA256( ASCII(verifier) ) ) == challenge.
    def pkce_matches?(challenge, verifier)
      return false if challenge.blank? || verifier.blank?

      digest = Digest::SHA256.digest(verifier.to_s)
      computed = Base64.urlsafe_encode64(digest, padding: false)
      ActiveSupport::SecurityUtils.secure_compare(computed, challenge.to_s)
    end

    def key(code)
      "#{KEY_PREFIX}#{code}"
    end

    def redis
      defined?($redis) ? $redis : nil
    end
    private_class_method :pkce_matches?, :key, :redis
  end
end
