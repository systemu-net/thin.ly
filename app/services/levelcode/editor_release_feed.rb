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
    # Feed target → the release asset that serves it. Squirrel installs a .zip of the signed .app, so
    # that is the only INSTALLABLE artifact (the .dmg is the human download). Matching on an exact
    # filename means an Intel app can never be handed the arm64 build.
    # Only macOS builds ship today — announcing on other targets would notify users of a build
    # that does not exist for them.
    ASSET_FOR_TARGET = {
      "darwin-arm64" => "LevelCode-arm64.app.zip",
      "darwin" => "LevelCode-x64.app.zip"
    }.freeze
    TARGETS = ASSET_FOR_TARGET.keys.freeze
    CACHE_KEY = "levelcode:editor_release_feed:latest"
    CACHE_TTL = 5.minutes

    def latest(target:, quality:)
      return nil unless quality.to_s == "stable" && TARGETS.include?(target.to_s)

      # One GitHub lookup serves every target; the arch-specific asset is resolved per call.
      cached = Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { fetch_release || :none }
      return nil if cached == :none

      entry_for(cached, target.to_s)
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
        page_url: rel["html_url"].presence || RELEASES_PAGE,
        # arch => { url:, sha256: } for each signed .app.zip on this release. Empty for releases cut
        # before signed assets shipped — those stay notify-only (see entry_for).
        assets: build_assets(rel["assets"]),
        timestamp: rel["published_at"].present? ? Time.zone.parse(rel["published_at"]).to_i : 0
      }
    end

    # Resolve the cached release to ONE target's feed entry.
    #
    # `installable` is the load-bearing bit: true only when this arch has a signed .app.zip, i.e. when
    # the built-in Squirrel updater could actually install it. Releases without one still serve the
    # release PAGE so the notify-only updater keeps working — but the controller must never hand a page
    # to Squirrel, which would auto-download a web page and fail.
    def entry_for(rel, target)
      asset = rel[:assets][target]
      {
        commit: rel[:commit],
        product_version: rel[:product_version],
        url: asset ? asset[:url] : rel[:page_url],
        sha256hash: asset && asset[:sha256],
        timestamp: rel[:timestamp],
        release_notes_url: rel[:page_url],
        installable: asset.present?
      }
    end

    # Pick the signed .app.zip per arch by EXACT filename — an unknown or renamed asset is ignored
    # rather than guessed at, so a cross-arch zip can never be served.
    def build_assets(list)
      Array(list).each_with_object({}) do |a, out|
        target = ASSET_FOR_TARGET.key(a["name"].to_s)
        next if target.nil?

        url = a["browser_download_url"].to_s
        next if url.blank?

        out[target] = { url: url, sha256: sha256_from(a["digest"]) }
      end
    end

    # GitHub reports asset digests as "sha256:<hex>" (and may omit them entirely); the feed wants bare hex.
    def sha256_from(digest)
      d = digest.to_s
      d.start_with?("sha256:") ? d.delete_prefix("sha256:").presence : nil
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
