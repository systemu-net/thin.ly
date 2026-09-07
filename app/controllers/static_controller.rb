class StaticController < ApplicationController
  # Hosts that serve the LevelCode Cloud account app (levelcode.html shell) instead of
  # the thin.ly shortener SPA. The account app always lives under /ai/* on every
  # host (the /ai prefix never collides with the 7-char shortcode lookup), so the
  # brand switch is PATH-based; these hosts additionally funnel bare HTML paths
  # into /ai so levelcode.ai/pricing → /ai/pricing. (Non-HTML bare paths 404, which
  # is correct — the account app has no non-HTML bare endpoints; the JSON API is
  # under /api/levelcode/v1/*.)
  # ENV-overridable so a staging or tunnel host (ngrok, a preview deploy) can serve the account app.
  # MUST be set together with LEVELCODE_ORIGIN: overriding the origin alone points the bounce at a host
  # that is still not recognised as a LevelCode host, and /ai then 301s to itself forever. The
  # self-redirect guard in #ui makes that misconfiguration render instead of loop, but set both.
  DEFAULT_LEVELCODE_HOSTS = "levelcode.ai,www.levelcode.ai"
  def self.parse_hosts(raw)
    raw.to_s.split(",").map { |h| h.strip.downcase }.reject(&:empty?)
  end
  LEVELCODE_HOSTS = parse_hosts(ENV.fetch("LEVELCODE_HOSTS", DEFAULT_LEVELCODE_HOSTS)).freeze
  # Canonical origin LevelCode Cloud lives on. thin.ly bounces any /ai request here so the account app
  # only ever opens on a LevelCode host. ENV-overridable for staging.
  LEVELCODE_ORIGIN = ENV.fetch("LEVELCODE_ORIGIN", "https://levelcode.ai").freeze

  # Strict host↔brand isolation:
  #   • a LevelCode host serves ONLY the account app (levelcode shell); bare paths funnel into /ai and
  #     it never renders the thin.ly shortener shell.
  #   • the thin.ly (shortener) host NEVER serves the account app; any /ai request is bounced to the
  #     canonical LevelCode origin so LevelCode Cloud can't be opened from thin.ly/ai.
  def ui
    if levelcode_host?
      return redirect_to(ai_funnel_dest) unless ai_path?

      render "static/ui_levelcode", layout: false
    else
      # Never bounce a host to itself. If LEVELCODE_ORIGIN resolves to the host already being asked,
      # a 301 here is an infinite loop — the browser follows it straight back to this action. That is
      # what a half-applied staging override produces (LEVELCODE_ORIGIN set, LEVELCODE_HOSTS not), and
      # a config mistake should degrade to "serves the app" rather than to a redirect storm.
      return render("static/ui_levelcode", layout: false) if ai_path? && origin_is_self?
      return redirect_to("#{LEVELCODE_ORIGIN}#{request.fullpath}", allow_other_host: true, status: :moved_permanently) if ai_path?

      render "static/ui", layout: false
    end
  end

  def unsafe_link
    response.set_header("X-Robots-Tag", "noindex, nofollow")
    render "static/unsafe_link", status: :forbidden, layout: false
  end

  def link_not_found
    response.set_header("X-Robots-Tag", "noindex, nofollow")
    render "static/link_not_found", status: :not_found, layout: false
  end

  def not_found
    response.set_header("X-Robots-Tag", "noindex, nofollow")
    render file: Rails.root.join("public", "404.html"), status: :not_found, layout: false
  end

  private

  def levelcode_host?
    LEVELCODE_HOSTS.include?(request.host.to_s.downcase)
  end

  # True when the canonical origin IS this request's host — i.e. redirecting would target ourselves.
  def origin_is_self?
    URI.parse(LEVELCODE_ORIGIN).host.to_s.casecmp?(request.host.to_s)
  rescue URI::InvalidURIError
    false
  end

  def ai_path?
    request.path == "/ai" || request.path.start_with?("/ai/")
  end

  # Map a bare LevelCode-host path onto the /ai app: / → /ai, /pricing → /ai/pricing (keeps the query).
  def ai_funnel_dest
    dest = request.path == "/" ? "/ai" : "/ai#{request.path}"
    request.query_string.present? ? "#{dest}?#{request.query_string}" : dest
  end
end
