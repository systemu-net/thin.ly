# LevelCode editor update feed — the Code-OSS update contract the desktop editor speaks.
#
# The editor GETs  /api/update/:target/:quality/:commit  (e.g. darwin-arm64/stable/<sha>) and expects:
#   • 204 No Content  → up to date (no error, no notification)
#   • 200 { version, productVersion, url, sha256hash, timestamp, releaseNotesUrl }  → a newer build exists
#     (`version` is the LATEST build's commit; the editor notifies when it differs from the running commit).
#
# Today this returns 204 (up to date): it makes the editor's "Check for Updates" report "Up to Date"
# instead of "The server sent an invalid response" (the old 404 that broke both the native Squirrel updater
# and the levelcode-updater extension). Real in-app updates on macOS need a Developer-ID-signed .zip feed
# asset (Squirrel.Mac auto-installs + verifies the signature) — until that ships, users update via the
# download page and this feed stays quiet. Populate LEVELCODE_UPDATE_FEED to switch it on.
#
# FAIL-SAFE: this endpoint must NEVER return 5xx or HTML — the native updater and the extension both treat
# anything that isn't 204/valid-JSON as an error. Any exception or unknown release resolves to 204.
class Api::UpdatesController < ApplicationController
  RELEASE_NOTES_FALLBACK = "https://github.com/levelcodeai/levelcode/releases/latest".freeze

  def show
    response.set_header("Cache-Control", "no-store")

    rel = latest_release(params[:target], params[:quality])
    # 204 (up to date) when there's nothing published, the entry is INCOMPLETE (missing a field the updater
    # needs to install — a 200 with null url/version would re-trigger the "invalid response"), or the
    # running build is already the latest.
    return head(:no_content) if rel.blank? ||
                                rel[:commit].blank? || rel[:url].blank? || rel[:product_version].blank? ||
                                rel[:commit] == params[:commit]

    render json: {
      version: rel[:commit], # the latest build's commit — the editor compares this to the running commit
      productVersion: rel[:product_version],
      url: rel[:url],        # signed .zip feed asset (Squirrel.Mac downloads + installs it)
      sha256hash: rel[:sha256hash],
      timestamp: rel[:timestamp] || 0,
      releaseNotesUrl: rel[:release_notes_url].presence || RELEASE_NOTES_FALLBACK
    }
  rescue StandardError => e
    Rails.logger.warn("[Api::Updates] #{e.class}: #{e.message} — serving 204 (up to date)")
    head :no_content
  end

  private

  # The latest published build for a target/quality, or nil. Config-driven (LEVELCODE_UPDATE_FEED, a JSON
  # map) so the feed is fast and can't be rate-limited; absent/empty → nil → 204 (the notify-via-site state).
  #   LEVELCODE_UPDATE_FEED = {"darwin-arm64":{"stable":{"commit":"…","product_version":"0.4.0",
  #                            "url":"…signed.zip","sha256hash":"…","timestamp":0,"release_notes_url":"…"}}}
  def latest_release(target, quality)
    return nil if target.blank? || quality.blank?

    entry = parsed_feed.dig(target.to_s, quality.to_s)
    entry.is_a?(Hash) ? entry.symbolize_keys : nil
  end

  def parsed_feed
    raw = ENV["LEVELCODE_UPDATE_FEED"].presence
    parsed = raw ? JSON.parse(raw) : {}
    # Valid JSON that isn't an object (e.g. `null`, `[]`, a scalar) → treat as empty, so `latest_release`
    # never hits a NoMethodError on `dig` and gets shunted to the rescue path. Keeps behavior deterministic.
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError => e
    Rails.logger.warn("[Api::Updates] bad LEVELCODE_UPDATE_FEED JSON: #{e.message}")
    {}
  end
end
