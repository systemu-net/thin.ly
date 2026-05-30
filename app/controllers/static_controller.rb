class StaticController < ApplicationController
  def ui
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
end
