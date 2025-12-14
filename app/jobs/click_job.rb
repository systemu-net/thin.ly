require "sidekiq"

class ClickJob
  include Sidekiq::Job
  queue_as :default

  def perform(lookup_code, ip_address, user_agent, referrer, source = nil, cloudfront_headers = {})
    link = Link.find_by(lookup_code: lookup_code)
    return unless link

    # Parse User-Agent for browser and OS information
    parsed_ua = parse_user_agent(user_agent)

    # Build click attributes with CloudFront headers (if available) or fallback
    click_attributes = {
      ip_address: ip_address,
      user_agent: user_agent,
      referrer: referrer,
      source: source,

      # Geolocation data from CloudFront headers
      country: cloudfront_headers["country"],
      country_name: cloudfront_headers["country_name"],
      city: cloudfront_headers["city"],
      region: cloudfront_headers["region"],
      postal_code: cloudfront_headers["postal_code"],
      latitude: cloudfront_headers["latitude"],
      longitude: cloudfront_headers["longitude"],
      timezone: cloudfront_headers["timezone"],

      # Device type from CloudFront headers
      is_mobile: cloudfront_headers["is_mobile"] || false,
      is_tablet: cloudfront_headers["is_tablet"] || false,
      is_desktop: cloudfront_headers["is_desktop"] || false,

      # Determine primary device type
      device_type: determine_device_type(cloudfront_headers, parsed_ua),

      # Browser and OS from User-Agent parsing
      browser: parsed_ua[:browser],
      browser_version: parsed_ua[:browser_version],
      os: parsed_ua[:os],
      os_version: parsed_ua[:os_version],
      is_bot: parsed_ua[:is_bot]
    }

    link.clicks.create(click_attributes)
  end

  private

  def parse_user_agent(user_agent)
    return default_user_agent_data if user_agent.blank?

    # Simple bot detection
    is_bot = bot?(user_agent)

    # Extract browser information (simple parsing - can be enhanced with a gem)
    browser_data = extract_browser_info(user_agent)
    os_data = extract_os_info(user_agent)

    {
      browser: browser_data[:name],
      browser_version: browser_data[:version],
      os: os_data[:name],
      os_version: os_data[:version],
      is_bot: is_bot
    }
  end

  def bot?(user_agent)
    bot_patterns = [
      /bot/i, /crawl/i, /spider/i, /slurp/i, /mediapartners/i,
      /apis-google/i, /adsbot/i, /googlebot/i, /bingbot/i,
      /lighthouse/i, /pingdom/i, /headless/i
    ]
    bot_patterns.any? { |pattern| user_agent.match?(pattern) }
  end

  def extract_browser_info(user_agent)
    case user_agent
    when /Edge\/(\d+\.\d+)/i
      { name: "Edge", version: Regexp.last_match(1) }
    when /Edg\/(\d+\.\d+)/i
      { name: "Edge", version: Regexp.last_match(1) }
    when /Chrome\/(\d+\.\d+)/i
      { name: "Chrome", version: Regexp.last_match(1) }
    when /Safari\/(\d+\.\d+)/i
      { name: "Safari", version: Regexp.last_match(1) } unless user_agent.match?(/Chrome/i)
    when /Firefox\/(\d+\.\d+)/i
      { name: "Firefox", version: Regexp.last_match(1) }
    when /Opera\/(\d+\.\d+)/i, /OPR\/(\d+\.\d+)/i
      { name: "Opera", version: Regexp.last_match(1) }
    else
      { name: "Unknown", version: nil }
    end
  end

  def extract_os_info(user_agent)
    case user_agent
    when /Windows NT (\d+\.\d+)/i
      { name: "Windows", version: windows_version(Regexp.last_match(1)) }
    when /Mac OS X (\d+[_\.\d]+)/i
      { name: "macOS", version: Regexp.last_match(1).tr("_", ".") }
    when /iPhone OS (\d+[_\.\d]+)/i, /iOS (\d+[_\.\d]+)/i
      { name: "iOS", version: Regexp.last_match(1).tr("_", ".") }
    when /Android (\d+\.\d+)/i
      { name: "Android", version: Regexp.last_match(1) }
    when /Linux/i
      { name: "Linux", version: nil }
    else
      { name: "Unknown", version: nil }
    end
  end

  def windows_version(nt_version)
    versions = {
      "10.0" => "10",
      "6.3" => "8.1",
      "6.2" => "8",
      "6.1" => "7",
      "6.0" => "Vista"
    }
    versions[nt_version] || nt_version
  end

  def determine_device_type(cloudfront_headers, parsed_ua)
    return "bot" if parsed_ua[:is_bot]
    return "smarttv" if cloudfront_headers["is_smarttv"]
    return "tablet" if cloudfront_headers["is_tablet"]
    return "mobile" if cloudfront_headers["is_mobile"]
    return "desktop" if cloudfront_headers["is_desktop"]

    # Fallback based on User-Agent if CloudFront headers not available
    "unknown"
  end

  def default_user_agent_data
    {
      browser: "Unknown",
      browser_version: nil,
      os: "Unknown",
      os_version: nil,
      is_bot: false
    }
  end
end
