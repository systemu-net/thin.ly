# frozen_string_literal: true

module Api
  module Levelcode
    module V1
      # Base controller for the isolated LevelCode Cloud API (SPEC §3). Separate from
      # the link-shortener `Api::V1::*` stack: pure JSON, no CSRF/session cookies of
      # its own, HS256 editor tokens instead of the browser devise-jwt.
      #
      # `authenticate_levelcode!` accepts EITHER:
      #   - `Authorization: Bearer <editor access JWT>` — verified via
      #     ::Levelcode::EditorToken (sig + exp + scope + jti-not-revoked), OR
      #   - the levelcode.ai web session cookie — i.e. an already-signed-in Devise
      #     user (warden), used by `/account` and `/pricing` server calls.
      class BaseController < ActionController::API
        include ActionController::Cookies
        include Devise::Controllers::Helpers
        include AccessTracking

        before_action :authenticate_levelcode!
        before_action :enforce_abuse_caps!

        rescue_from ::Levelcode::EditorToken::InvalidToken do |e|
          render_levelcode_error("unauthorized", e.message, :unauthorized)
        end

        # The authenticated user for this request, resolved from either the editor
        # bearer token or the web session. Memoized.
        def current_levelcode_user
          @current_levelcode_user
        end

        # Alias so controllers written against the app-wide `current_user`
        # convention (the billing/account controllers mirror Api::V1) resolve the
        # levelcode-authenticated user. Overrides Devise's helper within this
        # namespace, which is intentional (this API is token-first, not session).
        def current_user
          current_levelcode_user
        end

        private

        # Verify the levelcode.ai server->backend service token (SPEC §1, §2). Used by
        # the trusted mint endpoint (auth#callback), which runs before any user
        # exists. Constant-time compare; renders 403 and returns false on mismatch.
        def verify_service_token!
          expected = ENV["LEVELCODE_SITE_SERVICE_TOKEN"].to_s
          presented = request.headers["X-Levelcode-Service-Token"].to_s
          if expected.present? && ActiveSupport::SecurityUtils.secure_compare(presented, expected)
            return true
          end

          render_levelcode_error("forbidden", "Invalid service token", :forbidden)
          false
        end

        # Primary gate. Sets @current_levelcode_user or renders 401.
        def authenticate_levelcode!
          @current_levelcode_user = user_from_bearer || user_from_session

          if @current_levelcode_user
            touch_access!(@current_levelcode_user) # denormalize last country/seen (throttled)
            return
          end

          render_levelcode_error("unauthorized", "Authentication required", :unauthorized)
        end

        # --- Bearer (editor access token) ---------------------------------------

        def user_from_bearer
          token = bearer_token
          return nil if token.blank?

          claims = ::Levelcode::EditorToken.verify(token, scope: "account:read")
          User.find_by(id: claims["sub"])
        end

        def bearer_token
          header = request.headers["Authorization"].to_s
          return nil unless header.start_with?("Bearer ")

          header.split(" ", 2).last&.strip
        end

        # Expose the verified claims (scope checks, jti for signout) to actions.
        def levelcode_token_claims
          return @levelcode_token_claims if defined?(@levelcode_token_claims)

          token = bearer_token
          @levelcode_token_claims = token.present? ? ::Levelcode::EditorToken.verify(token) : nil
        rescue ::Levelcode::EditorToken::InvalidToken
          @levelcode_token_claims = nil
        end

        # --- Web session cookie -------------------------------------------------

        def user_from_session
          # warden is populated by Devise's middleware from the session cookie.
          warden = request.env["warden"]
          warden&.authenticate(scope: :user)
        end

        # --- Abuse caps (SPEC §5) ----------------------------------------------

        # Thin stub: per-user RPM / daily token caps via Redis. Full enforcement
        # (concurrency, configurable limits, StatsD) lands with the metering slice;
        # this hook keeps the wiring and fails open when Redis is unavailable.
        def enforce_abuse_caps!
          return unless current_levelcode_user
          return unless abuse_redis

          user_id = current_levelcode_user.id
          rpm_key = "levelcode:rpm:#{user_id}:#{Time.now.to_i / 60}"
          count = abuse_redis.incr(rpm_key)
          abuse_redis.expire(rpm_key, 60) if count == 1

          if count > abuse_rpm_limit
            render_levelcode_error(
              "rate_limited",
              "Too many requests. Please slow down.",
              :too_many_requests
            )
          end
        rescue StandardError => e
          # Fail open: never let a Redis hiccup take the API down.
          Rails.logger.warn("Levelcode abuse-cap check failed: #{e.message}")
          nil
        end

        def abuse_rpm_limit
          (ENV["LEVELCODE_RPM_LIMIT"].presence || 120).to_i
        end

        def abuse_redis
          defined?($redis) ? $redis : nil
        end

        # --- Error helper (SPEC §3 envelope) -----------------------------------

        def render_levelcode_error(code, message, status)
          render json: { error: { code: code, message: message } }, status: status
        end
      end
    end
  end
end
