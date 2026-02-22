class Api::V1::TrackController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [ :view ]

  before_action :validate_origin

  # Handle CORS preflight
  def cors_preflight
    head :ok
  end

  def view
    lookup_code = params[:lookup_code]
    brand_page = BrandPage.find_by(lookup_code: lookup_code)

    unless brand_page
      return render json: { error: "Brand page not found" }, status: :not_found
    end

    # Extract request data
    request_data = {
      ip_address: request_ip,
      user_agent: request.user_agent,
      referrer: request.referrer,
      country: request.headers["CF-IPCountry"] || extract_country_from_ip,
      city: request.headers["CF-IPCity"],
      region: request.headers["CF-Region"],
      browser: extract_browser,
      browser_version: extract_browser_version,
      os: extract_os,
      os_version: extract_os_version,
      device_type: extract_device_type,
      visited_at: Time.current
    }

    # Track the view
    page_view = PageView.track_view(brand_page, request_data)

    if page_view.persisted?
      render json: { success: true }, status: :ok
    else
      render json: { error: "Failed to track view", details: page_view.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def validate_origin
    origin = request.headers["Origin"]

    # Check if origin matches *.thin.ly
    unless origin =~ /\Ahttps:\/\/.*\.thin\.ly\z/ || origin =~ /\Ahttp:\/\/localhost:(3000|4000)\z/ || origin == ENV["DEV_HOST"]
      render json: { error: "Invalid origin" }, status: :forbidden
    end
  end

  def request_ip
    # Handle X-Forwarded-For header from proxies/load balancers
    forwarded_for = request.headers["X-Forwarded-For"]
    if forwarded_for.present?
      forwarded_for.split(",").first.strip
    else
      request.remote_ip
    end
  end

  def extract_country_from_ip
    # Placeholder - in production you'd use a GeoIP service
    nil
  end

  def extract_browser
    user_agent = request.user_agent.to_s
    case user_agent
    when /Chrome/i then "Chrome"
    when /Safari/i then "Safari"
    when /Firefox/i then "Firefox"
    when /Edge/i then "Edge"
    when /Opera/i then "Opera"
    else "Unknown"
    end
  end

  def extract_browser_version
    user_agent = request.user_agent.to_s
    case user_agent
    when /Chrome\/(\d+\.\d+\.\d+\.\d+)/i
      Regexp.last_match(1)
    when /Safari\/(\d+\.\d+)/i
      Regexp.last_match(1)
    when /Firefox\/(\d+\.\d+)/i
      Regexp.last_match(1)
    else
      nil
    end
  end

  def extract_os
    user_agent = request.user_agent.to_s
    case user_agent
    when /iPhone|iPad|iPod/i then "iOS"
    when /Android/i then "Android"
    when /Windows/i then "Windows"
    when /Macintosh|Mac OS X/i then "macOS"
    when /Linux/i then "Linux"
    else "Unknown"
    end
  end

  def extract_os_version
    user_agent = request.user_agent.to_s
    case user_agent
    when /Mac OS X (\d+[_\.]\d+[_\.]\d+)/i
      Regexp.last_match(1).tr("_", ".")
    when /Windows NT (\d+\.\d+)/i
      Regexp.last_match(1)
    when /Android (\d+\.\d+)/i
      Regexp.last_match(1)
    when /iPhone OS (\d+[_\.]\d+)/i
      Regexp.last_match(1).tr("_", ".")
    else
      nil
    end
  end

  def extract_device_type
    user_agent = request.user_agent.to_s
    case user_agent
    when /Mobile|iPhone|iPod|Android.*Mobile/i then "mobile"
    when /iPad|Android/i then "tablet"
    else "desktop"
    end
  end
end
