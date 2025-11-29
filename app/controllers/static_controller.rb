class StaticController < ApplicationController
  def ui
  end

  def unsafe_link
    render "static/unsafe_link", status: :forbidden, layout: false
  end

  def not_found
    render file: Rails.root.join("public", "404.html"), status: :not_found, layout: false
  end
end
