# frozen_string_literal: true

module Levelcode
  # Passwordless email one-time-code (OTP) for LevelCode Cloud sign-in — the
  # OpenRouter/Cursor "magic code" flow: request a code by email, type it in,
  # you're in (SPEC §2, email method). Distinct from Levelcode::OneTimeCode, which
  # is the internal OAuth-style handoff to the editor AFTER auth.
  #
  # Security posture:
  #   - 6-digit numeric code, HMAC-hashed at rest (Redis leak != plaintext codes),
  #     bound to the email address.
  #   - 10-minute TTL, SINGLE-USE (deleted on first success).
  #   - MAX_ATTEMPTS online guesses per code, then the code is burned.
  #   - Per-email resend throttle (RESEND_WINDOW) to blunt email-bombing; the
  #     controller adds a per-IP cap on top.
  # A 6-digit code is 10^6; the attempt cap + single-use + short TTL bound online
  # brute force. (Widen to 8 digits if desired — CODE_DIGITS.)
  module EmailCode
    module_function

    TTL           = 10.minutes
    RESEND_WINDOW = 60.seconds
    MAX_ATTEMPTS  = 5
    CODE_DIGITS   = 6

    class Error < StandardError; end
    class RateLimited < Error; end

    # Issue a fresh code for `email`, store it hashed, return the plaintext code
    # for the caller to email. Raises RateLimited if one was issued < RESEND_WINDOW ago.
    def issue(email)
      raise Error, "redis unavailable" unless redis

      norm = normalize(email)
      # Redis#exists? returns a boolean (redis-rb >= 4.2).
      raise RateLimited, "code recently sent" if redis.exists?(resend_key(norm))

      code = format("%0#{CODE_DIGITS}d", SecureRandom.random_number(10**CODE_DIGITS))
      redis.setex(code_key(norm), TTL.to_i, digest(norm, code)) # store the hash only
      redis.del(attempts_key(norm))                             # fresh guess counter
      redis.setex(resend_key(norm), RESEND_WINDOW.to_i, "1")
      code
    end

    # Clear a pending code, its guess counter, and the resend throttle — used when
    # delivery failed so the user can request a new one immediately.
    def clear(email)
      return unless redis

      norm = normalize(email)
      redis.del(code_key(norm), attempts_key(norm), resend_key(norm))
    end

    # Verify `code` for `email`. Constant-time; single-use on success; attempt-capped.
    # Returns true/false (never raises for a bad code).
    def verify(email, code)
      return false if email.blank? || code.blank?
      raise Error, "redis unavailable" unless redis

      norm = normalize(email)
      stored = redis.get(code_key(norm))
      return false if stored.blank?

      # Atomic attempt cap: INCR a sibling counter so parallel wrong guesses can't
      # race past MAX_ATTEMPTS (a Ruby-side read-modify-write would undercount and
      # let an attacker exceed the cap against the 10^6 space within the TTL).
      attempts = redis.incr(attempts_key(norm))
      redis.expire(attempts_key(norm), TTL.to_i) if attempts == 1
      if attempts > MAX_ATTEMPTS
        redis.del(code_key(norm), attempts_key(norm)) # burn the code
        return false
      end

      if ActiveSupport::SecurityUtils.secure_compare(stored.to_s, digest(norm, code))
        redis.del(code_key(norm), attempts_key(norm)) # single-use
        true
      else
        false
      end
    end

    # --- internals -----------------------------------------------------------

    def normalize(email)
      email.to_s.strip.downcase
    end

    def digest(email, code)
      OpenSSL::HMAC.hexdigest("SHA256", hmac_secret, "#{email}:#{code}")
    end

    def hmac_secret
      # Fail CLOSED — never degrade to a constant. This HMAC key is the only
      # at-rest protection for OTP hashes; a known key makes them brute-forceable
      # offline (10^6). Mirrors Levelcode::EditorToken#secret.
      ENV["LEVELCODE_JWT_SECRET"].presence ||
        (defined?(Rails) && Rails.application.credentials.dig(:levelcode_jwt_secret)) ||
        raise(Error, "LEVELCODE_JWT_SECRET is not configured")
    end

    def code_key(email)
      "levelcode:emailcode:#{email}"
    end

    def resend_key(email)
      "levelcode:emailcode:sent:#{email}"
    end

    def attempts_key(email)
      "levelcode:emailcode:attempts:#{email}"
    end

    def redis
      defined?($redis) ? $redis : nil
    end
    private_class_method :normalize, :digest, :hmac_secret, :code_key, :resend_key, :attempts_key, :redis
  end
end
