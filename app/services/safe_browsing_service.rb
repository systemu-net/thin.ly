class SafeBrowsingService
  CACHE_TTL = ENV.fetch("SAFE_BROWSING_CACHE_TTL", 86400).to_i
  API_TIMEOUT = 10 # seconds

  THREAT_TYPE_SEVERITY = {
    "MALWARE" => "HIGH",
    "SOCIAL_ENGINEERING" => "HIGH",
    "UNWANTED_SOFTWARE" => "MEDIUM",
    "POTENTIALLY_HARMFUL_APPLICATION" => "MEDIUM",
    "THREAT_TYPE_UNSPECIFIED" => "LOW"
  }.freeze

  def initialize
    @client = Google::Apis::SafebrowsingV4::SafebrowsingService.new
    @client.key = ENV["GOOGLE_SAFE_BROWSING_API_KEY"] || Rails.application.credentials.fetch(:google_safe_browsing_api_key)
    # @client.request_options.timeout_sec = API_TIMEOUT
  end

  # Main method to check a single URL
  def check_url(url)
    normalized_url = normalize_url(url)

    # Check cache first
    cached = get_cached_result(normalized_url)
    return cached if cached

    # Call API
    result = call_api([ normalized_url ])
    threats = parse_threats(result, normalized_url)

    # Cache result
    cache_result(normalized_url, threats)

    threats
  rescue Google::Apis::Error => e
    Rails.logger.error("Safe Browsing API error: #{e.message}")
    { safe: true, threats: [], cached: false, error: e.message }
  end

  # Batch check multiple URLs (up to 500 at once)
  def batch_check_urls(urls)
    normalized_urls = urls.map { |url| normalize_url(url) }
    results = {}

    # Separate cached and uncached URLs
    uncached = []
    normalized_urls.each do |url|
      cached = get_cached_result(url)
      if cached
        results[url] = cached
      else
        uncached << url
      end
    end

    # Check uncached URLs in batches of 500
    uncached.each_slice(500) do |batch|
      api_result = call_api(batch)
      batch.each do |url|
        threats = parse_threats(api_result, url)
        cache_result(url, threats)
        results[url] = threats
      end
    end

    results
  end

  private

  def call_api(urls)
    request = Google::Apis::SafebrowsingV4::GoogleSecuritySafebrowsingV4FindThreatMatchesRequest.new(
      client: {
        client_id: "thinly",
        client_version: "1.0.0"
      },
      threat_info: {
        threat_types: [
          "MALWARE",
          "SOCIAL_ENGINEERING",
          "UNWANTED_SOFTWARE",
          "POTENTIALLY_HARMFUL_APPLICATION"
        ],
        platform_types: [ "ANY_PLATFORM" ],
        threat_entry_types: [ "URL" ],
        threat_entries: urls.map { |url| { url: url } }
      }
    )

    @client.find_threat_matches(request)
  end

  def parse_threats(api_result, url)
    matches = api_result&.matches&.select { |m| m.threat&.url == url } || []

    if matches.empty?
      { safe: true, threats: [], threat_types: [], cached: false }
    else
      threat_types = matches.map { |m| m.threat_type }.uniq
      severity = determine_severity(threat_types)

      {
        safe: false,
        threats: matches,
        threat_types: threat_types,
        platform_types: matches.map { |m| m.platform_type }.uniq,
        severity: severity,
        cached: false
      }
    end
  end

  def determine_severity(threat_types)
    threat_types.map { |t| THREAT_TYPE_SEVERITY[t] || "LOW" }
                .max_by { |s| [ "HIGH", "MEDIUM", "LOW" ].index(s) }
  end

  def normalize_url(url)
    uri = URI.parse(url)
    "#{uri.scheme}://#{uri.host}#{uri.path}".downcase
  rescue URI::InvalidURIError
    url.downcase
  end

  def cache_key(url)
    "safe_browsing:#{Digest::SHA256.hexdigest(url)}"
  end

  def get_cached_result(url)
    cached = $redis.get(cache_key(url))
    return nil unless cached

    result = JSON.parse(cached, symbolize_names: true)
    result[:cached] = true
    result
  end

  def cache_result(url, result)
    result_to_cache = result.dup
    result_to_cache.delete(:cached)
    $redis.setex(cache_key(url), CACHE_TTL, result_to_cache.to_json)
  end
end
