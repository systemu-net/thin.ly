class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # allow_browser versions: :modern

  def log_api_request(logable)
    current_user.plan.api_requests.create(logable: logable)
  end

  def check_api_limit
    return unless current_user.plan.send("#{controller_name}_limit_exceeded?".to_sym)

    render json: { error: "API request limit reached. Do You want to upgrade the plan?" }, status: :too_many_requests
  end
end
