class StaticController < ApplicationController
  # Hosts that serve the LevelCode Cloud account app (levelcode.html shell) instead of
  # the thin.ly shortener SPA. The account app always lives under /ai/* on every
  # host (the /ai prefix never collides with the 7-char shortcode lookup), so the
  # brand switch is PATH-based; these hosts additionally funnel bare HTML paths
  # into /ai so levelcode.ai/pricing → /ai/pricing. (Non-HTML bare paths 404, which
  # is correct — the account app has no non-HTML bare endpoints; the JSON API is
  # under /api/levelcode/v1/*.)
  LEVELCODE_HOSTS = %w[levelcode.ai www.levelcode.ai].freeze
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
    LEVELCODE_HOSTS.include?(request.host)
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
