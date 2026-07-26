# frozen_string_literal: true

require "uri"
require "cgi"

module Levelcode
  # Server-side auth/session/billing flows for the LevelCode Cloud account app
  # (the onetime SPA served at /ai/*). The SPA renders the pages and reads data
  # from the JSON API (Api::Levelcode::V1::* — pricing, account/profile+usage); this
  # controller owns only the flows that MUST run server-side:
  #   - OAuth authorize + callback (client-secret code exchange), and
  #   - the session-establishing / Stripe WRITES (CSRF-protected, cookie session).
  #
  # It uses the standard Devise web session (sign_in / current_user) and Rails
  # CSRF — the SPA sends the token from the shell's <meta name="csrf-token">.
  #
  # Sign-in delivers TWO ways (SHARED CONTRACT):
  #   - editor: an `levelcode://…/auth/callback` redirect_uri is present ->
  #     mint a single-use Levelcode::OneTimeCode bound to the editor's PKCE
  #     code_challenge and hand back `<redirect_uri>?code=<code>` (never tokens).
  #   - web: Devise sign_in(user) -> destination /ai/account.
  class WebController < ApplicationController
    include AccessTracking

    # Browser/session surface — restore real CSRF (ApplicationController defaults
    # to :null_session for the token-first API). The SPA's state-changing POSTs
    # carry X-CSRF-Token from the shell meta; OAuth start/callback are GETs.
    protect_from_forgery with: :exception

    before_action :authenticate_user!, only: %i[checkout billing authorize_editor]

    # The frozen editor deep-link callback (SHARED CONTRACT). Host = the extension id
    # <publisher>.<name> = levelcode.levelcode-ai; path = /auth/callback.
    EDITOR_CALLBACK = "levelcode://levelcode.levelcode-ai/auth/callback"
    # Accepted url schemes for the editor deep-link. `levelcode` is the current product urlProtocol;
    # `atom-plus-plus` is the pre-rename scheme, still emitted by editor builds not yet rebuilt —
    # accepted during the transition. The security-relevant host + path stay strictly pinned.
    EDITOR_SCHEMES = %w[levelcode atom-plus-plus].freeze

    # Per-IP OTP-send cap. The recipient is caller-chosen, so EmailCode's per-email
    # resend window alone can be fanned out across many addresses — bound by source IP.
    EMAIL_SEND_WINDOW = 1.hour.to_i
    EMAIL_SEND_MAX = 20

    # POST /ai/auth/email  (JSON) — passwordless step 1: email a 6-digit code.
    def email_request
      email = params[:email].to_s.strip.downcase
      return render_error("invalid_email", "Enter a valid email address.", :unprocessable_content) unless valid_email?(email)
      return render_error("rate_limited", "Too many sign-in attempts from your network. Please wait a bit and try again.", :too_many_requests) unless email_send_allowed?

      begin
        code = Levelcode::EmailCode.issue(email)
        # deliver_now: send immediately + keep the plaintext code out of the job queue.
        LevelcodeAuthMailer.login_code(email, code).deliver_now
      rescue Levelcode::EmailCode::RateLimited
        # A live code was just sent — succeed silently (no resend spam).
        Rails.logger.info("[Levelcode web OTP] resend throttled")
      rescue StandardError => e
        Levelcode::EmailCode.clear(email)
        Rails.logger.error("[Levelcode web OTP] issue failed: #{e.class}: #{e.message}")
        return render_error("email_failed", "Could not send the code. Please try again.", :bad_gateway)
      end

      render json: { sent: true }
    end

    # POST /ai/auth/verify  (JSON) — step 2. Body: { email, code, redirect_uri?, code_challenge? }.
    # The editor threads redirect_uri + code_challenge as params (there is no
    # server-rendered login page to stash them in session first).
    def email_verify
      @redirect_uri = editor_redirect_uri(params[:redirect_uri])
      @code_challenge = editor_code_challenge(params[:code_challenge])
      email = params[:email].to_s.strip.downcase

      unless Levelcode::EmailCode.verify(email, params[:code])
        log_auth(kind: "email", outcome: "failure", email: email, reason: "invalid_code")
        return render_error("invalid_code", "That code is invalid or has expired.", :unauthorized)
      end

      user = find_or_create_email_user(email, params[:attribution])
      unless user&.persisted?
        log_auth(kind: "email", outcome: "failure", email: email, reason: "account_error")
        return render_error("account_error", "Could not sign you in. Please try again.", :unprocessable_content)
      end

      log_auth(kind: "email", outcome: "success", user: user)
      touch_access!(user)
      dest = deliver_signed_in(user)
      return render_error("link_expired", "Your sign-in link expired. Please start again from the editor.", :unprocessable_content) unless dest

      render json: { redirect: dest }
    end

    # GET /ai/auth/oauth/:provider  — full-page nav from the SPA. Persist an
    # anti-CSRF `state` (+ carry the editor context) in the session, 302 to the
    # provider. The provider redirect_uri is always OUR fixed web callback.
    def oauth_start
      provider = params[:provider].to_s
      (redirect_to("/ai/login") and return) unless %w[github google].include?(provider)

      stash_editor_context(safe_redirect_uri(params[:redirect_uri]), params[:code_challenge].presence)

      state = SecureRandom.urlsafe_base64(24)
      session[:levelcode_oauth_state] = state
      session[:levelcode_oauth_provider] = provider
      # Carry the SPA's first-touch marketing attribution across the provider
      # round-trip. It rides the session (like `state`) rather than the provider
      # redirect, so it can't be tampered with at the provider and comes back to
      # the same browser. Clamped because the session lives in a 4 KB cookie and
      # this value is client-supplied; it is sanitized again before it reaches
      # the DB (see stamp_oauth_attribution!).
      session[:levelcode_oauth_attribution] = params[:attribution].to_s[0, 2_000].presence

      url = Levelcode::ProviderOAuth.authorize_url(provider: provider, redirect_uri: oauth_callback_uri, state: state)
      redirect_to url, allow_other_host: true
    end

    # GET /ai/auth/callback  — OAuth return: verify session `state`, exchange the
    # code server-side, then either 302 to the editor deep-link (with a one-time
    # code) or sign in and 302 to /ai/account.
    def oauth_callback
      provider = session.delete(:levelcode_oauth_provider).to_s
      expected_state = session.delete(:levelcode_oauth_state).to_s
      raw_attribution = session.delete(:levelcode_oauth_attribution)

      if expected_state.blank? || params[:state].to_s != expected_state
        log_auth(kind: "oauth", outcome: "failure", provider: provider, reason: "session_expired")
        return redirect_to("/ai/login?error=session_expired")
      end

      user =
        case provider
        when "github" then Levelcode::ProviderOAuth.github_user(code: params[:code], redirect_uri: oauth_callback_uri)
        when "google" then Levelcode::ProviderOAuth.google_user(code: params[:code], redirect_uri: oauth_callback_uri)
        end

      unless user&.persisted?
        log_auth(kind: "oauth", outcome: "failure", provider: provider, reason: "oauth_failed")
        return redirect_to("/ai/login?error=oauth_failed")
      end

      stamp_oauth_attribution!(user, raw_attribution)

      log_auth(kind: "oauth", outcome: "success", user: user, provider: provider)
      touch_access!(user)
      @redirect_uri = editor_redirect_uri
      @code_challenge = editor_code_challenge
      dest = deliver_signed_in(user)
      redirect_to(dest || "/ai/login?error=link_expired", allow_other_host: true)
    end

    # GET /ai/auth/handoff?code=…  — the editor->browser direction of the shared
    # contract. Redeem a single-use code minted by /api/levelcode/v1/auth/web_handoff
    # (issuable only by a holder of the user's editor token) and sign the SAME user
    # into a Devise web session, then land on /ai/account — so "Manage account" from
    # the editor doesn't force a second sign-in. Invalid/expired/Redis-down → /ai/login.
    def handoff
      user = Levelcode::OneTimeCode.redeem(params[:code])
      sign_in(user)
      redirect_to("/ai/account")
    rescue Levelcode::OneTimeCode::Error
      redirect_to("/ai/login?error=link_expired")
    end

    # POST /ai/authorize_editor  (JSON, authenticate_user!) — the "Open IDE" completion step.
    # The EDITOR initiates its normal PKCE sign-in (it holds the verifier) and opens /ai/login
    # with its `redirect_uri` + `code_challenge`; when the browser already has a session, the SPA
    # calls this to mint a PKCE-BOUND one-time code and hand back the editor deep-link — so no
    # second login. FAILS CLOSED without a valid editor deep-link + challenge: an UNBOUND code
    # would be interceptable via the custom scheme and redeemable at /auth/exchange for full
    # editor tokens (the exact posture deliver_signed_in enforces). Binding the code to the
    # editor-held verifier means an intercepted code is useless without it.
    def authorize_editor
      redirect_uri = safe_redirect_uri(params[:redirect_uri])
      challenge = editor_code_challenge(params[:code_challenge])
      if redirect_uri.blank? || challenge.blank?
        return render_error("invalid_request", "Not a valid editor sign-in request.", :unprocessable_content)
      end

      code = Levelcode::OneTimeCode.issue(current_user, challenge)
      render json: { redirect: editor_callback_with_code(redirect_uri, code) }
    end

    # POST /ai/checkout  (JSON, authenticate_user!) — start a subscription, or change plan in place.
    #
    # First purchase → a Stripe Checkout Session; returns { url } for the SPA to redirect to.
    # Existing active levelcode subscription → change the plan on the SAME Stripe subscription via
    # Levelcode::PlanChange (upgrade: immediate prorated charge for the difference; downgrade: a Stripe
    # subscription schedule that keeps the current, higher tier until period end, so the customer keeps the
    # allowance they already paid for). Returns { status: "plan_changed", … } with no url. Mirrors
    # Api::Levelcode::V1::CheckoutsController#handle_plan_change. Previously this ALWAYS opened a new
    # Checkout Session, which charged the full new price and could leave a duplicate subscription.
    def checkout
      lookup_key = params[:lookup_key].to_s
      prices = Stripe::Price.list(lookup_keys: [ lookup_key ], expand: [ "data.product" ])
      price = prices.data[0]
      return render_error("plan_unavailable", "That plan is unavailable.", :unprocessable_content) unless price

      subscription = current_user.subscriptions.find_by(product: "levelcode")
      if subscription&.subscription_id.present? && subscription.status.in?(%w[active trialing past_due])
        change_levelcode_plan(subscription.subscription_id, price)
      else
        session_obj = Stripe::Checkout::Session.create(
          customer: current_user.stripe_id,
          mode: "subscription",
          client_reference_id: current_user.id,
          line_items: [ { quantity: 1, price: price.id } ],
          success_url: absolute_url("/ai/account"),
          cancel_url: absolute_url("/ai/pricing")
        )
        render json: { url: session_obj.url }
      end
    rescue Stripe::StripeError => e
      Rails.logger.error("[Levelcode web checkout] #{e.class}: #{e.message}")
      render_error("stripe_error", "Could not start checkout. Please try again.", :bad_gateway)
    end

    # POST /ai/billing  (JSON, authenticate_user!) — Stripe billing portal.
    def billing
      session_obj = Stripe::BillingPortal::Session.create(
        customer: current_user.stripe_id,
        return_url: absolute_url("/ai/account")
      )
      render json: { url: session_obj.url }
    rescue Stripe::StripeError => e
      Rails.logger.error("[Levelcode web billing] #{e.class}: #{e.message}")
      render_error("stripe_error", "Could not open billing. Please try again.", :bad_gateway)
    end

    # POST/DELETE /ai/signout  (JSON) — the SPA navigates to /ai/login after.
    def signout
      sign_out(current_user) if current_user
      render json: { ok: true }
    end

    # GET /ai/csrf  (JSON) — same-origin CSRF token for the SPA in dev. The prod
    # shell embeds this via <meta name="csrf-token">; the Vite dev shell can't,
    # so `api.ts` fetches one here. Same-origin only — CORS prevents cross-origin
    # reads, so this exposes nothing the prod meta tag doesn't already.
    def csrf
      render json: { token: form_authenticity_token }
    end

    private

    # --- Delivery (SHARED CONTRACT: editor deep-link vs web session) ----------

    # Returns the post-sign-in destination URL (editor deep-link carrying a
    # one-time code, or the web account path) and establishes the Devise session
    # for the web path. Returns nil to FAIL CLOSED (editor deep-link with no PKCE
    # challenge — an unbound one-time code would be interceptable).
    def deliver_signed_in(user)
      clear_editor_context

      if editor_deep_link?(@redirect_uri)
        return nil if @code_challenge.blank?

        code = Levelcode::OneTimeCode.issue(user, @code_challenge)
        editor_callback_with_code(@redirect_uri, code)
      else
        sign_in(user)
        "/ai/account"
      end
    end

    def editor_callback_with_code(uri_str, code)
      uri = URI.parse(uri_str)
      query = uri.query.present? ? Hash[URI.decode_www_form(uri.query)] : {}
      query["code"] = code
      uri.query = URI.encode_www_form(query)
      uri.to_s
    end

    # --- redirect_uri validation (no open redirect, never tokens in a URL) ----
    #
    # Accept ONLY the editor deep-link, pinned by scheme + host + path. We must
    # tolerate a query string (VS Code's asExternalUri appends ?windowId=N to route
    # the callback to the right editor window) and percent-encoding (the value can
    # arrive single- OR double-encoded through the login → OAuth hops), but NOTHING
    # else — no https, no other host/path — so this stays closed to open-redirect
    # abuse (D36). Returns the DECODED deep-link WITH its query so the caller can
    # append the one-time code without dropping the window routing.
    def safe_redirect_uri(raw)
      return nil if raw.blank?

      candidate = decode_deep_link(raw)
      editor_deep_link?(candidate) ? candidate : nil
    end

    # Decode until stable — handles single- or double-encoded values; capped.
    def decode_deep_link(raw)
      s = raw.to_s
      3.times do
        break unless s.include?("%")
        decoded = CGI.unescape(s)
        break if decoded == s
        s = decoded
      end
      s
    end

    # True when uri_str is the editor callback deep-link. Scheme + host + path are
    # pinned to EDITOR_CALLBACK; any query (e.g. ?windowId=N) is allowed and gets
    # preserved by editor_callback_with_code.
    def editor_deep_link?(uri_str)
      return false if uri_str.blank?

      u = URI.parse(uri_str.to_s)
      e = URI.parse(EDITOR_CALLBACK)
      EDITOR_SCHEMES.include?(u.scheme) && u.host == e.host && u.path == e.path
    rescue URI::InvalidURIError
      false
    end

    # --- Session-stashed editor context (OAuth round-trip) --------------------

    def stash_editor_context(redirect_uri, code_challenge)
      if redirect_uri.present?
        session[:levelcode_editor_redirect_uri] = redirect_uri
        # Never DOWNGRADE an already-bound flow: only (re)write the challenge when
        # one is actually supplied (a re-link that omits it must not null it out,
        # which would make the minted one-time code PKCE-unbound).
        session[:levelcode_editor_code_challenge] = code_challenge if code_challenge.present?
      else
        clear_editor_context
      end
    end

    def clear_editor_context
      session.delete(:levelcode_editor_redirect_uri)
      session.delete(:levelcode_editor_code_challenge)
    end

    # Resolve the editor redirect_uri from an explicit param (re-validated) or the
    # session stash; nil means the web session path. Email verify passes params;
    # OAuth reads the session stashed at oauth_start.
    def editor_redirect_uri(param = nil)
      safe_redirect_uri(param) || session[:levelcode_editor_redirect_uri].presence
    end

    def editor_code_challenge(param = nil)
      param.presence || session[:levelcode_editor_code_challenge].presence
    end

    # --- Helpers --------------------------------------------------------------

    # Passwordless find-or-create; a random password satisfies Devise validatable
    # and is never used (sign-in is OTP/OAuth only). On the CREATE path only, stamp the first-touch
    # marketing attribution the SPA sent — an existing user keeps whatever acquired them (acquisition
    # attribution, not last-touch).
    def find_or_create_email_user(email, attribution = nil)
      User.find_by(email: email) || User.create(
        email: email,
        password: Devise.friendly_token[0, 32],
        terms_accepted: true,
        signup_attribution: sanitize_signup_attribution(attribution)
      )
    rescue ActiveRecord::RecordNotUnique
      # Two sign-ins for the same NEW email raced between the find_by and the INSERT, and the unique index
      # on users.email rejected the loser. Re-find the winner so a valid sign-in never 500s. (Attribution
      # was stamped by whichever request won the create; the loser just returns the existing account.)
      User.find_by(email: email)
    end

    # Stamp first-touch attribution on a user who just signed up via OAuth.
    #
    # The email path can pass attribution straight into User.create; OAuth cannot,
    # because GitHub and Google create the user through two different services
    # (ProviderOAuth.find_or_create_oauth_user and User.from_google). Doing it here
    # keeps one rule in one place for both providers.
    #
    # Two guards, and both matter for whether a partner's numbers mean anything:
    #   * previously_new_record? — stamp ONLY on the create. Someone who signed up
    #     months ago and today happens to arrive via a referral link was not
    #     acquired by that channel; crediting them would be last-touch and would
    #     inflate the partner's conversions.
    #   * signup_attribution.nil? — never overwrite an existing value.
    def stamp_oauth_attribution!(user, raw)
      return unless user&.persisted? && user.previously_new_record?
      return unless user.signup_attribution.nil?

      attribution = sanitize_signup_attribution(parse_attribution_json(raw))
      return if attribution.nil?

      # update_column: skip validations/callbacks — this is analytics metadata and
      # must never be able to fail a sign-in that already succeeded.
      user.update_column(:signup_attribution, attribution)
    rescue StandardError => e
      # Attribution is best-effort. A signed-in user must not be bounced to an
      # error page because a marketing field could not be written.
      Rails.logger.warn("[levelcode] oauth attribution stamp failed: #{e.class}: #{e.message}")
    end

    # The session carries the SPA's attribution as the JSON string it put in the
    # URL. Anything unparseable is simply organic — never an error.
    def parse_attribution_json(raw)
      return nil if raw.blank?

      parsed = JSON.parse(raw.to_s)
      parsed.is_a?(Hash) ? parsed : nil
    rescue JSON::ParserError
      nil
    end

    # Campaign params we recognize (mirror of the SPA's attribution util). Anything else is dropped.
    ATTRIBUTION_PARAM_KEYS = %w[linkedin youtube ref utm_source utm_medium utm_campaign utm_content].freeze

    # Coerce the CLIENT-CONTROLLED attribution blob (query params → localStorage → request body) into a
    # small, bounded, whitelisted hash before it touches the DB — never store the raw params object. Returns
    # nil for organic/absent/garbage input so the column stays null.
    def sanitize_signup_attribution(raw)
      h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
      return nil unless h.is_a?(Hash)

      src = h["params"] || h[:params]
      params = {}
      if src.is_a?(Hash)
        ATTRIBUTION_PARAM_KEYS.each do |k|
          v = src[k] || src[k.to_sym]
          params[k] = v.to_s[0, 120] if v.present?
        end
      end
      source = h["source"].to_s[0, 40]
      return nil if params.empty? && source.blank?

      {
        "source" => source.presence || "other",
        "params" => params,
        "landing" => h["landing"].to_s[0, 300].presence,
        "referrer" => h["referrer"].to_s[0, 300].presence,
        "ts" => h["ts"].to_s[0, 40].presence,
        "recorded_at" => Time.current.utc.iso8601
      }.compact
    end

    def valid_email?(email)
      email.present? && email.match?(URI::MailTo::EMAIL_REGEXP)
    end

    # Per-IP OTP-send throttle (EMAIL_SEND_MAX per EMAIL_SEND_WINDOW). Best-effort:
    # allows the send if Redis is unavailable rather than locking users out.
    def email_send_allowed?
      r = defined?($redis) && $redis
      return true unless r

      key = "levelcode:web:emailsend:#{request.remote_ip}"
      count = r.incr(key)
      r.expire(key, EMAIL_SEND_WINDOW) if count == 1
      count <= EMAIL_SEND_MAX
    rescue StandardError => e
      Rails.logger.warn("[Levelcode web OTP] throttle check failed: #{e.class}: #{e.message}")
      true
    end

    # Our fixed web OAuth callback (absolute, host-derived) — the provider
    # redirect_uri for BOTH authorize and the token exchange.
    def oauth_callback_uri
      absolute_url("/ai/auth/callback")
    end

    def absolute_url(path)
      "#{request.base_url}#{path}"
    end

    def render_error(code, message, status)
      render json: { error: { code: code, message: message } }, status: status
    end

    # Change the plan on an existing levelcode subscription IN PLACE (via Levelcode::PlanChange) instead of
    # opening a second full-price Checkout Session. Upgrade → immediate prorated swap; downgrade → a
    # subscription schedule that defers the switch to period end (see the service for why). Stripe errors
    # bubble to #checkout's rescue; a same-plan re-purchase is a 422 already_subscribed.
    def change_levelcode_plan(stripe_sub_id, new_price)
      result = Levelcode::PlanChange.call(
        user: current_user, subscription_id: stripe_sub_id, new_price: new_price
      )
      render json: { status: "plan_changed", change_type: result.change_type, message: result.message }
    rescue Levelcode::PlanChange::SamePlanError
      render_error("already_subscribed", "You're already on this plan.", :unprocessable_content)
    end
  end
end
