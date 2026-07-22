# frozen_string_literal: true

require "net/http"
require "uri"

module Levelcode
  # Server-side OAuth code-exchange + find/create-user for GitHub & Google
  # (SPEC §2). Extracted verbatim from the private methods that lived in
  # Api::Levelcode::V1::AuthController so BOTH the JSON API (site -> backend mint)
  # and the Rails-served web account surface (Levelcode::WebController) share one
  # hardened implementation.
  #
  # Security posture (unchanged from the controller original):
  #   - GitHub: ONLY the VERIFIED PRIMARY email is trusted — never the
  #     user-editable public profile field, which an attacker could set to a
  #     victim's address to link into their account.
  #   - Google: the returned id_token is cryptographically verified against the
  #     configured client id(s) before any account is touched.
  #   - The https/levelcode redirect_uri validation stays in the callers
  #     (this module receives an already-decided redirect_uri and passes it
  #     straight through to the provider token endpoint so the exchange matches
  #     the authorize step).
  module ProviderOAuth
    module_function

    GITHUB_PROVIDER = "github"

    GITHUB_AUTHORIZE_URL = "https://github.com/login/oauth/authorize"
    GITHUB_TOKEN_URL     = "https://github.com/login/oauth/access_token"
    GOOGLE_AUTHORIZE_URL = "https://accounts.google.com/o/oauth2/v2/auth"
    GOOGLE_TOKEN_URL     = "https://oauth2.googleapis.com/token"

    # Exchange a GitHub authorization `code` (obtained with `redirect_uri`) for an
    # access token, fetch the user + verified primary email, then find-or-create
    # the local user. Returns a User or nil.
    def github_user(code:, redirect_uri:)
      return nil if code.blank?

      access_token = github_exchange_code(code, redirect_uri)
      return nil if access_token.blank?

      gh_user = github_get("https://api.github.com/user", access_token)
      return nil unless gh_user

      # ONLY a verified primary email — never gh_user["email"] (the user-editable
      # public profile field), which would let an attacker set a victim's address
      # and link into their account. Mirrors the Google email_verified guard.
      email = github_primary_email(access_token)
      return nil if email.blank?

      find_or_create_oauth_user(
        provider: GITHUB_PROVIDER,
        uid: gh_user["id"].to_s,
        email: email.to_s.downcase,
        name: gh_user["name"].presence || gh_user["login"]
      )
    end

    # Server-side authorization-code flow for Google (site/web forwards the
    # provider `code`). Exchange it with Google's token endpoint (client secret +
    # the SAME redirect_uri used for authorize + PKCE verifier), verify the
    # returned id_token, then find-or-create the user. Returns a User or nil.
    def google_user(code:, redirect_uri:, verifier: nil)
      return nil if code.blank?

      id_token = google_exchange_code(code, redirect_uri, verifier)
      return nil if id_token.blank?

      payload = verify_google_id_token(id_token)
      return nil unless payload

      User.from_google(payload)
    end

    # Build the provider `authorize` URL the browser is redirected to. `state` is
    # the CSRF/session-binding token; `code_challenge` (S256) enables PKCE so the
    # matching verifier is required at the token exchange. Returns a String.
    def authorize_url(provider:, redirect_uri:, state:, code_challenge: nil)
      case provider.to_s
      when "github"
        build_url(GITHUB_AUTHORIZE_URL, {
          client_id: ENV["GITHUB_OAUTH_ID"],
          redirect_uri: redirect_uri,
          scope: "read:user user:email",
          state: state,
          # GitHub honours S256 PKCE on the OAuth app flow.
          code_challenge: code_challenge,
          code_challenge_method: code_challenge.present? ? "S256" : nil,
          allow_signup: "true"
        })
      when "google"
        build_url(GOOGLE_AUTHORIZE_URL, {
          client_id: google_client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: "openid email profile",
          state: state,
          code_challenge: code_challenge,
          code_challenge_method: code_challenge.present? ? "S256" : nil,
          access_type: "online",
          prompt: "select_account"
        })
      else
        raise ArgumentError, "unknown provider: #{provider}"
      end
    end

    # --- GitHub internals ----------------------------------------------------

    def github_exchange_code(code, redirect_uri)
      res = post_form(
        GITHUB_TOKEN_URL,
        {
          client_id: ENV["GITHUB_OAUTH_ID"],
          client_secret: ENV["GITHUB_OAUTH_SECRET"],
          code: code,
          redirect_uri: redirect_uri
        },
        headers: { "Accept" => "application/json" }
      )
      return nil unless res

      JSON.parse(res)["access_token"]
    rescue JSON::ParserError
      nil
    end

    def github_primary_email(access_token)
      emails = github_get("https://api.github.com/user/emails", access_token)
      return nil unless emails.is_a?(Array)

      primary = emails.find { |e| e["primary"] && e["verified"] }
      primary && primary["email"]
    end

    def github_get(url, access_token)
      uri = URI.parse(url)
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{access_token}"
      req["Accept"] = "application/vnd.github+json"
      req["User-Agent"] = "levelcode"

      body = perform_http(uri, req)
      body && JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    # --- Google internals ----------------------------------------------------

    # The Google "Web application" OAuth client for the LevelCode auth-code flow. Falls back to the
    # already-configured GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET (the same client thin.ly's GIS login
    # uses) when a dedicated GOOGLE_OAUTH_ID / GOOGLE_OAUTH_SECRET isn't set — so bringing Google to
    # levelcode.ai needs only the client SECRET added to the env, not a duplicate client id. The id_token
    # `aud` is validated against google_client_ids, which already includes GOOGLE_CLIENT_ID.
    def google_client_id
      ENV["GOOGLE_OAUTH_ID"].presence || ENV["GOOGLE_CLIENT_ID"]
    end

    def google_client_secret
      ENV["GOOGLE_OAUTH_SECRET"].presence || ENV["GOOGLE_CLIENT_SECRET"]
    end

    def google_exchange_code(code, redirect_uri, verifier)
      res = post_form(
        GOOGLE_TOKEN_URL,
        {
          client_id: google_client_id,
          client_secret: google_client_secret,
          code: code,
          redirect_uri: redirect_uri,
          grant_type: "authorization_code",
          code_verifier: verifier
        },
        headers: { "Accept" => "application/json" }
      )
      return nil unless res

      JSON.parse(res)["id_token"]
    rescue JSON::ParserError
      nil
    end

    # Mirror Users::GoogleAuthController#verify_google_id_token.
    def verify_google_id_token(id_token)
      Google::Auth::IDTokens.verify_oidc(id_token, aud: google_client_ids)
    rescue Google::Auth::IDTokens::VerificationError => e
      Rails.logger.warn("Google ID token verification failed: #{e.message}")
      nil
    end

    def google_client_ids
      ids = [ ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_OAUTH_ID"] ]
        .compact.flat_map { |v| v.to_s.split(",") }.map(&:strip).reject(&:empty?).uniq
      ids.size == 1 ? ids.first : ids
    end

    # --- Local user find-or-create (OAuth) -----------------------------------

    def find_or_create_oauth_user(provider:, uid:, email:, name: nil)
      user = User.find_by(provider: provider, uid: uid) || User.find_by(email: email)

      if user
        user.update(provider: provider, uid: uid) if user.uid.blank?
        user
      else
        User.create(
          provider: provider,
          uid: uid,
          email: email,
          password: Devise.friendly_token[0, 20],
          terms_accepted: true
        )
      end
    end

    # --- HTTP helpers --------------------------------------------------------

    def build_url(base, query)
      uri = URI.parse(base)
      uri.query = URI.encode_www_form(query.compact)
      uri.to_s
    end

    def post_form(url, form, headers: {})
      uri = URI.parse(url)
      req = Net::HTTP::Post.new(uri)
      headers.each { |k, v| req[k] = v }
      req["User-Agent"] = "levelcode"
      req.set_form_data(form.compact)

      perform_http(uri, req)
    end

    def perform_http(uri, req)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      res = http.request(req)
      res.is_a?(Net::HTTPSuccess) ? res.body : nil
    rescue StandardError => e
      Rails.logger.warn("Levelcode OAuth HTTP error: #{e.message}")
      nil
    end

    private_class_method :github_exchange_code, :github_primary_email, :github_get,
                         :google_exchange_code, :verify_google_id_token, :google_client_ids,
                         :google_client_id, :google_client_secret,
                         :find_or_create_oauth_user, :build_url, :post_form, :perform_http
  end
end
