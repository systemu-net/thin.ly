class StaticController < ApplicationController
  # Hosts that serve the LevelCode Cloud account app (levelcode.html shell) instead of
  # the thin.ly shortener SPA. The account app always lives under /ai/* on every
  # host (the /ai prefix never collides with the 7-char shortcode lookup), so the
  # brand switch is PATH-based; these hosts additionally funnel bare HTML paths
  # into /ai so levelcode.ai/pricing → /ai/pricing. (Non-HTML bare paths 404, which
  # is correct — the account app has no non-HTML bare endpoints; the JSON API is
  # under /api/levelcode/v1/*.)
  LEVELCODE_HOSTS = %w[levelcode.ai www.levelcode.ai].freeze

  def ui
    # On an LevelCode host, redirect bare (non-/ai) paths into the /ai-mounted app.
    if levelcode_host? && !ai_path?
      dest = request.path == "/" ? "/ai" : "/ai#{request.path}"
      dest += "?#{request.query_string}" if request.query_string.present?
      return redirect_to(dest)
    end

    render(ai_path? ? "static/ui_levelcode" : "static/ui", layout: false)
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
end
