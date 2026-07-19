# LevelCode editor update feed — the Code-OSS update contract the desktop editor speaks.
#
# The editor GETs  /api/update/:target/:quality/:commit  (e.g. darwin-arm64/stable/<sha>) and expects:
#   • 204 No Content  → up to date (no error, no notification)
#   • 200 { version, productVersion, url, sha256hash, timestamp, releaseNotesUrl }  → a newer build exists
#     (`version` is the LATEST build's commit; the editor notifies when it differs from the running commit).
#
# The release source, in priority order:
#   1. LEVELCODE_UPDATE_FEED (env JSON) — the manual override/pin, and later the home of signed
#      .zip feed assets (Squirrel.Mac auto-installs + verifies the signature).
#   2. GitHub Releases (Levelcode::EditorReleaseFeed, cached 5 min) — the zero-maintenance default:
#      publishing a release on levelcodeai/levelcode IS the announcement.
#
# UNSIGNED-BUILD GUARD: the built-in Squirrel updater AUTO-DOWNLOADS a 200's url and installs it, so it
# is served a release only when BOTH hold: (a) signed feed assets are declared live
# (LEVELCODE_UPDATE_FEED_SIGNED=1), and (b) the resolved entry is INSTALLABLE — i.e. a signed
# `LevelCode-<arch>.app.zip` exists for that arch, not just a release page. Releases cut before signed
# assets shipped therefore stay notify-only even with the flag on. Everything else gets 204; the
# notify-only levelcode-updater extension — which merely OPENS the url — is always safe to serve.
# Producer side + rollout order: docs/AUTO-UPDATE.md in the editor repo.
#
# FAIL-SAFE: this endpoint must NEVER return 5xx or HTML — the native updater and the extension both treat
# anything that isn't 204/valid-JSON as an error. Any exception or unknown release resolves to 204.
class Api::UpdatesController < ApplicationController
  RELEASE_NOTES_FALLBACK = "https://github.com/levelcodeai/levelcode/releases/latest".freeze
  NOTIFY_ONLY_UA_PREFIX = "LevelCode Updater".freeze

  def show
    response.set_header("Cache-Control", "no-store")

    rel = latest_release(params[:target], params[:quality])
    # 204 (up to date) when there's nothing published, the entry is INCOMPLETE (missing a field the updater
    # needs to install — a 200 with null url/version would re-trigger the "invalid response"), or the
    # running build is already the latest.
    return head(:no_content) if rel.blank? ||
                                rel[:commit].blank? || rel[:url].blank? || rel[:product_version].blank? ||
                                rel[:commit] == params[:commit]

    # Unsigned-build guard (see class comment): a newer build exists, but only the notify-only
    # extension may hear about it until signed feed assets ship. The built-in Squirrel updater
    # additionally requires an INSTALLABLE entry — a signed .app.zip for this arch — so that flipping
    # LEVELCODE_UPDATE_FEED_SIGNED early can't hand it a release page to auto-download and choke on.
    return head(:no_content) unless notify_only_client? || (signed_feed? && rel[:installable])

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

  # The notify-only levelcode-updater extension identifies itself; the built-in Squirrel updater
  # (and anything else) does not.
  def notify_only_client?
    request.user_agent.to_s.start_with?(NOTIFY_ONLY_UA_PREFIX)
  end

  # Signed .zip feed assets are live — every client (incl. Squirrel auto-install) may take the 200.
  def signed_feed?
    ENV["LEVELCODE_UPDATE_FEED_SIGNED"] == "1"
  end

  # The latest published build for a target/quality, or nil. The env feed (LEVELCODE_UPDATE_FEED, a JSON
  # map) wins when it has an entry — the manual pin / signed-asset home; otherwise fall back to the
  # cached GitHub Releases lookup. Absent both → nil → 204.
  #   LEVELCODE_UPDATE_FEED = {"darwin-arm64":{"stable":{"commit":"…","product_version":"0.4.0",
  #                            "url":"…signed.zip","sha256hash":"…","timestamp":0,"release_notes_url":"…"}}}
  def latest_release(target, quality)
    return nil if target.blank? || quality.blank?

    entry = parsed_feed.dig(target.to_s, quality.to_s)
    # An operator-pinned entry is assumed INSTALLABLE — pinning a signed asset is the whole point of the
    # override. Set "installable": false in the JSON to pin a notify-only announcement instead.
    return { installable: true }.merge(entry.symbolize_keys) if entry.is_a?(Hash)

    Levelcode::EditorReleaseFeed.latest(target: target, quality: quality)
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
