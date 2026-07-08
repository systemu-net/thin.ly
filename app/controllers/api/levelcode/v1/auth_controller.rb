# frozen_string_literal: true

require "uri"
require "cgi"

module Api
  module Levelcode
    module V1
      # Auth surface for the LevelCode editor + levelcode.ai site (SPEC §2, §3).
      #
      # Browser flows (`oauth`, `login`, `signup`) authenticate the user and then,
      # when an editor `redirect_uri` is present, 302 back to it. Default hardened
      # path carries `?code=<one_time_code>` (PKCE S256, TTL 60s, single-use); a
      # `?token=<access>&refresh=…` fallback is also built (SPEC §2.1 — "both paths
      # built, code is default").
      #
      # Machine flows (`exchange`, `refresh`, `signout`) return JSON tokens.
      class AuthController < BaseController
        # These are all public / self-authenticating except signout + web_handoff
        # (both require a valid editor token).
        skip_before_action :authenticate_levelcode!, except: [ :signout, :web_handoff ]
        skip_before_action :enforce_abuse_caps!

        # POST /api/levelcode/v1/auth/callback  (levelcode.ai server -> backend)
        # Service-token authed. The site has completed the provider `authorize`
        # step and forwards the provider `code` (+ its own PKCE verifier + the
        # exact redirect_uri it used for authorize, so the token exchange matches).
        # We exchange the code, find/create the user, and return either a one-time
        # editor `code` (mode:"editor") or access/refresh + session (mode:"web").
        # Body: { provider, code, verifier, redirect_uri, mode, code_challenge? }
        def callback
          return unless verify_service_token!

          user =
            case params[:provider].to_s
            when "github"
              ::Levelcode::ProviderOAuth.github_user(code: params[:code], redirect_uri: params[:redirect_uri])
            when "google"
              ::Levelcode::ProviderOAuth.google_user(
                code: params[:code],
                redirect_uri: params[:redirect_uri],
                verifier: params[:verifier]
              )
            else
              return render_levelcode_error("invalid_provider", "Unknown provider", :bad_request)
            end

          unless user&.persisted?
            return render_levelcode_error("unauthorized", "OAuth authentication failed", :unauthorized)
          end

          render_mint_result(user)
        end

        # POST /api/levelcode/v1/auth/email/request  (levelcode.ai server -> backend)
        # Passwordless sign-in, step 1: email a 6-digit code. Always returns 200
        # (never reveals whether the address exists — any email can sign up on
        # verify). Service-token authed; the site adds a per-IP cap on top.
        def email_request
          return unless verify_service_token!

          email = params[:email].to_s.strip.downcase
          unless valid_email?(email)
            return render_levelcode_error("invalid_email", "A valid email is required", :unprocessable_content)
          end

          begin
            code = ::Levelcode::EmailCode.issue(email)
            # deliver_now (not _later): send immediately and keep the plaintext code
            # out of the Sidekiq/Redis job queue. raise_delivery_errors surfaces SMTP failures.
            LevelcodeAuthMailer.login_code(email, code).deliver_now
          rescue ::Levelcode::EmailCode::RateLimited
            # A code was just sent and is still valid — succeed silently (no resend spam).
            Rails.logger.info("[Levelcode email OTP] resend throttled")
          rescue StandardError => e
            # Delivery failed: drop the just-issued code + resend throttle so the
            # user can request another immediately (they never got this one).
            ::Levelcode::EmailCode.clear(email)
            Rails.logger.error("[Levelcode email OTP] issue failed: #{e.class}: #{e.message}")
            return render_levelcode_error("email_failed", "Could not send the code. Please try again.", :bad_gateway)
          end

          render json: { sent: true }, status: :ok
        end

        # POST /api/levelcode/v1/auth/email/verify  (levelcode.ai server -> backend)
        # Passwordless sign-in, step 2. Body: { email, code, redirect_uri?, mode?, code_challenge? }.
        def email_verify
          return unless verify_service_token!

          email = params[:email].to_s.strip.downcase
          unless ::Levelcode::EmailCode.verify(email, params[:code])
            return render_levelcode_error("invalid_code", "That code is invalid or has expired", :unauthorized)
          end

          user = user_from_email(email)
          unless user&.persisted?
            return render_levelcode_error("account_error", "Could not sign you in", :unprocessable_content)
          end

          render_mint_result(user)
        end

        # GET/POST /api/levelcode/v1/auth/login  (browser)
        def login
          user = User.find_for_database_authentication(email: login_params[:email].to_s.downcase)

          unless user&.valid_password?(login_params[:password])
            log_auth(kind: "login", outcome: "failure", email: login_params[:email], reason: "invalid_credentials")
            return render_levelcode_error("invalid_credentials", "Invalid email or password", :unauthorized)
          end

          log_auth(kind: "login", outcome: "success", user: user)
          touch_access!(user)
          deliver_browser_result(user)
        end

        # POST /api/levelcode/v1/auth/signup  (browser)
        def signup
          user = User.new(
            email: signup_params[:email].to_s.downcase,
            password: signup_params[:password],
            terms_accepted: ActiveModel::Type::Boolean.new.cast(signup_params[:terms])
          )

          if user.save
            deliver_browser_result(user)
          else
            render_levelcode_error(
              "signup_failed",
              user.errors.full_messages.to_sentence.presence || "Could not create account",
              :unprocessable_content
            )
          end
        end

        # POST /api/levelcode/v1/auth/exchange  (editor, hardened PKCE)
        # Body: { code, verifier } -> { access, refresh, profile }
        def exchange
          user = ::Levelcode::OneTimeCode.redeem(params[:code], params[:verifier])
          log_auth(kind: "exchange", outcome: "success", user: user)
          touch_access!(user)
          render json: token_bundle(user).merge(profile: profile_for(user)), status: :ok
        rescue ::Levelcode::OneTimeCode::InvalidVerifier => e
          log_auth(kind: "exchange", outcome: "failure", reason: "invalid_verifier")
          render_levelcode_error("invalid_verifier", e.message, :unauthorized)
        rescue ::Levelcode::OneTimeCode::Error => e
          log_auth(kind: "exchange", outcome: "failure", reason: "invalid_code")
          render_levelcode_error("invalid_code", e.message, :unauthorized)
        end

        # POST /api/levelcode/v1/auth/refresh  (editor)
        # Body: { refresh } -> { access }
        def refresh
          claims = ::Levelcode::EditorToken.verify(params[:refresh], scope: "refresh")
          user = User.find_by(id: claims["sub"])
          return render_levelcode_error("unauthorized", "User not found", :unauthorized) unless user

          render json: { access: ::Levelcode::EditorToken.mint_access(user) }, status: :ok
        rescue ::Levelcode::EditorToken::InvalidToken => e
          render_levelcode_error("invalid_refresh", e.message, :unauthorized)
        end

        # POST /api/levelcode/v1/auth/signout  (editor, bearer)
        # Revokes the presented access token's jti.
        def signout
          claims = levelcode_token_claims
          ::Levelcode::EditorToken.revoke!(claims["jti"]) if claims

          render json: { ok: true }, status: :ok
        end

        # POST /api/levelcode/v1/auth/web_handoff  (editor, bearer)
        # Hand the editor's authenticated identity to the browser: mint a single-use,
        # 60s one-time code and return the URL that redeems it into a Devise web session
        # and lands on /ai/account — so "Manage account" from the editor doesn't force a
        # second browser sign-in. Only a holder of THIS user's editor token can mint it
        # (the action is authed); the code is unbound (redeemed server-side at
        # /ai/auth/handoff), single-use, and short-lived.
        def web_handoff
          code = ::Levelcode::OneTimeCode.issue(current_levelcode_user)
          render json: { url: "#{request.base_url}/ai/auth/handoff?code=#{CGI.escape(code)}" }, status: :ok
        end

        private

        # --- Browser result delivery (SPEC §2.1) --------------------------------

        # If the caller supplied an editor `redirect_uri`, 302 to it carrying
        # either a one-time `code` (default, hardened) or the `token`/`refresh`
        # pair (fallback). Otherwise return the token bundle + profile as JSON.
        def deliver_browser_result(user)
          uri = safe_redirect_uri(params[:redirect_uri])

          if uri
            redirect_to build_callback_url(uri, user), allow_other_host: true
          else
            render json: token_bundle(user).merge(profile: profile_for(user)), status: :ok
          end
        end

        def build_callback_url(uri, user)
          query = existing_query(uri)
          # Always hand back a single-use code (never raw tokens in the URL, which
          # leak into browser history / Referer / proxy logs). The editor redeems
          # it at /auth/exchange. (SPEC §2.1; the client-selectable token_fallback
          # was removed — see the review's auth findings.)
          query["code"] = ::Levelcode::OneTimeCode.issue(user, params[:code_challenge])
          uri.query = URI.encode_www_form(query)
          uri.to_s
        end

        def existing_query(uri)
          uri.query.present? ? Hash[URI.decode_www_form(uri.query)] : {}
        end

        # Allow ONLY the frozen editor deep-link callback or the levelcode.ai origin.
        # A bare scheme check is an open redirect: build_callback_url appends the
        # one-time code (and, previously, raw tokens) to the query, so any allowed
        # host receives credentials. Pin exact host+path.
        def safe_redirect_uri(raw)
          return nil if raw.blank?

          uri = URI.parse(raw)
          # Editor deep-link: host = extension id (levelcode.levelcode-ai), path pinned. Accept the
          # current `levelcode` scheme and the legacy `atom-plus-plus` (pre-rename builds) during the
          # transition; host + path stay pinned so this can't become an open redirect.
          if %w[levelcode atom-plus-plus].include?(uri.scheme) && uri.host == "levelcode.levelcode-ai" && uri.path == "/auth/callback"
            return uri
          end

          site_host = URI(ENV["SITE_ORIGIN"].presence || "https://levelcode.ai").host
          return uri if uri.scheme == "https" && uri.host == site_host

          nil
        rescue URI::InvalidURIError
          nil
        end

        # --- Token / profile shaping -------------------------------------------

        # Shared editor-vs-web result for the mint endpoints (callback, email_verify).
        # Editor gets a one-time handoff code (redeemed at /auth/exchange, bound to
        # the editor's PKCE challenge); web gets access/refresh + a session token.
        def render_mint_result(user)
          if params[:mode].to_s == "editor"
            code = ::Levelcode::OneTimeCode.issue(user, params[:code_challenge])
            render json: { code: code, profile: profile_for(user) }, status: :ok
          else
            # Web session: a long-lived, account-scoped token for the levelcode.ai
            # cookie. Do NOT hand the web the editor's gateway (ai:*) access token.
            render json: { session: ::Levelcode::EditorToken.mint_session(user), profile: profile_for(user) }, status: :ok
          end
        end

        # Passwordless find-or-create (email OTP). New users get a random password
        # (Devise validatable requires one; it is never used — sign-in is OTP-only).
        def user_from_email(email)
          User.find_by(email: email) || User.create(
            email: email,
            password: Devise.friendly_token[0, 32],
            terms_accepted: true
          )
        end

        def valid_email?(email)
          email.present? && email.match?(URI::MailTo::EMAIL_REGEXP)
        end

        def token_bundle(user)
          {
            access: ::Levelcode::EditorToken.mint_access(user),
            refresh: ::Levelcode::EditorToken.mint_refresh(user)
          }
        end

        def profile_for(user)
          {
            name: user_display_name(user),
            email: user.email,
            plan: user_plan_key(user)
          }
        end

        def user_display_name(user)
          return user.name if user.respond_to?(:name) && user.name.present?

          user.email.to_s.split("@").first
        end

        # The LevelCode Cloud (Levelcode) plan for the editor profile — e.g. "Pro" — read
        # from the levelcode CreditWallet, NOT user.plan (the link-shortener
        # subscription, e.g. "Influencer", which is a different product entirely).
        def user_plan_key(user)
          key = CreditWallet.find_by(user: user, product: "levelcode")&.plan_key
          return nil if key.blank? || key == "free"

          ::Levelcode.plan(key)&.dig(:name) || key
        end

        # GitHub + Google server-side OAuth code-exchange (and the verified-email /
        # id_token security posture) now live in ::Levelcode::ProviderOAuth so the
        # Rails-served web account surface shares one hardened implementation.
        # `callback` delegates to ProviderOAuth.{github,google}_user directly.

        # --- Strong params ------------------------------------------------------

        def login_params
          params.permit(:email, :password)
        end

        def signup_params
          params.permit(:email, :password, :terms)
        end
      end
    end
  end
end
