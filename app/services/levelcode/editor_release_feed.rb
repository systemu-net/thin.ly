# frozen_string_literal: true

require "net/http"

module Levelcode
  # The GitHub-Releases-backed source for the editor update feed (Api::UpdatesController): the latest
  # published release of levelcodeai/levelcode, resolved to the Code-OSS feed-entry shape. Publishing
  # a GitHub release IS the whole announcement — no LEVELCODE_UPDATE_FEED JSON to hand-maintain per
  # release (that env var remains as an override/pin and as the home of signed assets later).
  #
  # Fail-safe by contract: ANY failure (network, rate limit, bad JSON) → nil → the controller's 204.
  # Cached — positive AND negative — for 5 minutes, so the feed answers fast and two lookups per TTL
  # stay far inside GitHub's anonymous rate limit (set GITHUB_FEED_TOKEN to lift it anyway).
  module EditorReleaseFeed
    module_function

    REPO = "levelcodeai/levelcode"
    RELEASES_PAGE = "https://github.com/#{REPO}/releases/latest"
    # Only macOS builds ship today — announcing on other targets would notify users of a build
    # that does not exist for them.
    TARGETS = %w[darwin darwin-arm64].freeze
    CACHE_KEY = "levelcode:editor_release_feed:latest"
    CACHE_TTL = 5.minutes

    def latest(target:, quality:)
      return nil unless quality.to_s == "stable" && TARGETS.include?(target.to_s)

      cached = Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { fetch_release || :none }
      cached == :none ? nil : cached
    rescue StandardError => e
      Rails.logger.warn("[Levelcode::EditorReleaseFeed] #{e.class}: #{e.message} — serving nil (→ 204)")
      nil
    end

    # ---- internals (stub `github_json` in specs) -------------------------------------------------

    def fetch_release
      rel = github_json("https://api.github.com/repos/#{REPO}/releases/latest")
      tag = rel && rel["tag_name"].presence
      return nil if tag.blank? || rel["draft"] || rel["prerelease"]

      # The feed contract compares COMMITS (product.json stamps the build's commit) — resolve the tag.
      head = github_json("https://api.github.com/repos/#{REPO}/commits/#{ERB::Util.url_encode(tag)}")
      sha = head && head["sha"].presence
      return nil if sha.blank?

      {
        commit: sha,
        product_version: tag.delete_prefix("v"),
        # The release PAGE, not a build asset: pre-signing, the only client served a 200 is the
        # notify-only updater, which merely OPENS this url. Signed .zip feed assets, when they ship,
        # get pinned via LEVELCODE_UPDATE_FEED (the env override wins over this fallback).
        url: rel["html_url"].presence || RELEASES_PAGE,
        sha256hash: nil,
        timestamp: rel["published_at"].present? ? Time.zone.parse(rel["published_at"]).to_i : 0,
        release_notes_url: rel["html_url"].presence || RELEASES_PAGE
      }
    end

    def github_json(url)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 3
      http.read_timeout = 3
      req = Net::HTTP::Get.new(uri)
      req["Accept"] = "application/vnd.github+json"
      req["User-Agent"] = "levelcode.ai update feed"
      token = ENV["GITHUB_FEED_TOKEN"].presence
      req["Authorization"] = "Bearer #{token}" if token
      res = http.request(req)
      res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : nil
    end
  end
end
