class StaticController < ApplicationController
  def ui
  end

  def not_found
    render file: Rails.root.join("public", "404.html"), status: :not_found, layout: false
  end
end
