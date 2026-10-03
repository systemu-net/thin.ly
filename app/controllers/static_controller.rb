class StaticController < ApplicationController
  # Strict host↔brand isolation:
  #   • a LevelCode host serves ONLY the account app (levelcode shell); bare paths funnel into /ai and
  #     it never renders the thin.ly shortener shell.
  #   • the thin.ly (shortener) host NEVER serves the account app; any /ai request is bounced to the
  #     canonical LevelCode origin so LevelCode Cloud can't be opened from thin.ly/ai.
  # Which hosts are LevelCode hosts, and where the canonical origin is, is Levelcode::Hosts' answer.
  #
  # The account app always lives under /ai/* on every host (the /ai prefix never collides with the
  # 7-char shortcode lookup), so the brand switch is PATH-based; LevelCode hosts additionally funnel
  # bare HTML paths into /ai so levelcode.ai/pricing → /ai/pricing. (Non-HTML bare paths 404, which
  # is correct — the account app has no non-HTML bare endpoints; the JSON API is under
  # /api/levelcode/v1/*.)
  def ui
    if levelcode_host?
      return redirect_to(ai_funnel_dest) unless ai_path?

      render "static/ui_levelcode", layout: false
    elsif ai_path?
      # Never bounce a host to itself. If the canonical origin resolves to the host already being
      # asked, a 301 here is an infinite loop — the browser follows it straight back to this action.
      # That is what a half-applied staging override produces (LEVELCODE_ORIGIN set, LEVELCODE_HOSTS
      # not), and a config mistake should degrade to "serves the app" rather than to a redirect storm.
      return render("static/ui_levelcode", layout: false) if origin_is_self?

      redirect_to "#{levelcode_hosts.origin}#{request.fullpath}", allow_other_host: true, status: :moved_permanently
    else
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

  def levelcode_hosts
    Levelcode::Hosts.current
  end

  def levelcode_host?
    levelcode_hosts.include?(request.host)
  end

  # True when the canonical origin IS this request's host — i.e. redirecting would target ourselves.
  def origin_is_self?
    levelcode_hosts.origin?(request.host)
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
