require "rails_helper"

# The LevelCode editor update feed (Code-OSS contract). See Api::UpdatesController.
RSpec.describe "Api::Updates", type: :request do
  UPDATE_URL = "/api/update/darwin-arm64/stable/abc123runningsha".freeze
  # The notify-only levelcode-updater extension's UA — pre-signing, the only client served a 200.
  NOTIFY_UA = { "User-Agent" => "LevelCode Updater" }.freeze

  FEED_VARS = %w[LEVELCODE_UPDATE_FEED LEVELCODE_UPDATE_FEED_SIGNED].freeze

  # Both vars are snapshotted, cleared for the example, and restored afterwards, so these specs neither
  # leak into each other NOR read the developer's shell. The `after`-only cleanup this replaces already
  # stopped the leak — but not the read: the FIRST example to run still saw the ambient value, and
  # `config.order = :random` picks which one that is. Measured: with LEVELCODE_UPDATE_FEED_SIGNED=1
  # exported, "serves 204 to the built-in Squirrel updater" gets a 200 and fails — on the seeds where it
  # happens to run first. A seed-dependent flake, not a clean red. `ensure` covers the failure path too.
  around do |example|
    saved = ENV.slice(*FEED_VARS)
    FEED_VARS.each { |k| ENV.delete(k) }
    example.run
  ensure
    FEED_VARS.each { |k| ENV.delete(k) }
    saved.each { |k, v| ENV[k] = v }
  end

  # No spec below may hit GitHub — the fallback is stubbed quiet unless a context opts in.
  before { allow(Levelcode::EditorReleaseFeed).to receive(:latest).and_return(nil) }

  def set_feed(map)
    ENV["LEVELCODE_UPDATE_FEED"] = map.to_json
  end

  describe "GET /api/update/:target/:quality/:commit" do
    context "with no feed configured (the current notify-via-site state)" do
      it "returns 204 up-to-date (so 'Check for Updates' no longer errors) with no-store" do
        get UPDATE_URL
        expect(response).to have_http_status(:no_content)
        expect(response.body).to eq("")
        expect(response.headers["Cache-Control"]).to include("no-store")
      end

      it "is public — never 401/redirect (the updater sends no credentials)" do
        get UPDATE_URL
        expect(response).to have_http_status(:no_content)
      end
    end

    context "when the running commit already matches the latest build" do
      before do
        set_feed("darwin-arm64" => { "stable" => { "commit" => "abc123runningsha", "product_version" => "0.4.0", "url" => "https://x/z.zip" } })
      end

      it "returns 204 (up to date)" do
        get UPDATE_URL
        expect(response).to have_http_status(:no_content)
      end
    end

    context "when a NEWER build exists for this target/quality" do
      before do
        set_feed("darwin-arm64" => { "stable" => {
          "commit" => "def456newsha", "product_version" => "0.5.0",
          "url" => "https://dl.levelcode.ai/LevelCode-arm64.zip", "sha256hash" => "deadbeef",
          "timestamp" => 1_720_000_000, "release_notes_url" => "https://github.com/levelcodeai/levelcode/releases/tag/v0.5.0"
        } })
      end

      it "returns 200 JSON in the exact Code-OSS feed shape (to the notify-only updater)" do
        get UPDATE_URL, headers: NOTIFY_UA
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["version"]).to eq("def456newsha") # editor notifies because != running commit
        expect(body["productVersion"]).to eq("0.5.0")
        expect(body["url"]).to eq("https://dl.levelcode.ai/LevelCode-arm64.zip")
        expect(body["sha256hash"]).to eq("deadbeef")
        expect(body["timestamp"]).to eq(1_720_000_000)
        expect(body["releaseNotesUrl"]).to eq("https://github.com/levelcodeai/levelcode/releases/tag/v0.5.0")
      end

      it "falls back to the GitHub releases page when the feed omits release_notes_url" do
        set_feed("darwin-arm64" => { "stable" => { "commit" => "def456newsha", "product_version" => "0.5.0", "url" => "https://x/z.zip" } })
        get UPDATE_URL, headers: NOTIFY_UA
        expect(response.parsed_body["releaseNotesUrl"]).to eq("https://github.com/levelcodeai/levelcode/releases/latest")
      end
    end

    context "UNSIGNED-BUILD GUARD — a newer build exists, but the client matters" do
      before do
        set_feed("darwin-arm64" => { "stable" => {
          "commit" => "def456newsha", "product_version" => "0.5.0", "url" => "https://x/z.zip"
        } })
      end

      it "serves 204 to the built-in Squirrel updater (it would auto-download and fail on unsigned builds)" do
        get UPDATE_URL, headers: { "User-Agent" => "LevelCode/0.5.0 Squirrel/1.0" }
        expect(response).to have_http_status(:no_content)
      end

      it "serves 204 to a UA-less client" do
        get UPDATE_URL
        expect(response).to have_http_status(:no_content)
      end

      it "serves the notify-only extension (it only OPENS the url, never installs it)" do
        get UPDATE_URL, headers: NOTIFY_UA
        expect(response).to have_http_status(:ok)
      end

      it "serves EVERY client once signed feed assets ship (LEVELCODE_UPDATE_FEED_SIGNED=1)" do
        ENV["LEVELCODE_UPDATE_FEED_SIGNED"] = "1"
        get UPDATE_URL, headers: { "User-Agent" => "LevelCode/0.5.0 Squirrel/1.0" }
        expect(response).to have_http_status(:ok)
      end

      context "when the entry is NOT installable (no signed .app.zip for this arch)" do
        before do
          # A release cut before signed assets shipped: `url` is a release PAGE. Auto-downloading a web
          # page would fail, so Squirrel must stay on 204 even if the SIGNED flag is flipped early.
          set_feed("darwin-arm64" => { "stable" => {
            "commit" => "def456newsha", "product_version" => "0.5.0",
            "url" => "https://github.com/levelcodeai/levelcode/releases/tag/v0.5.0",
            "installable" => false
          } })
        end

        it "serves 204 to Squirrel even with LEVELCODE_UPDATE_FEED_SIGNED=1" do
          ENV["LEVELCODE_UPDATE_FEED_SIGNED"] = "1"
          get UPDATE_URL, headers: { "User-Agent" => "LevelCode/0.5.0 Squirrel/1.0" }
          expect(response).to have_http_status(:no_content)
        end

        it "still serves the notify-only extension (it only opens the page)" do
          get UPDATE_URL, headers: NOTIFY_UA
          expect(response).to have_http_status(:ok)
        end
      end

      # Completes the pinned-`installable` tri-state: ABSENT defaults to installable (covered by "serves
      # EVERY client once signed feed assets ship" above), FALSE is the context above, and an explicit
      # JSON `null` is below. Null resolving to notify-only is a decision, not an accident — see the
      # comment on Api::UpdatesController#latest_release — so it gets a test that a refactor of the
      # `{ installable: true }.merge(...)` default would have to consciously delete.
      context "when the pinned entry sets installable to an explicit JSON null" do
        before do
          set_feed("darwin-arm64" => { "stable" => {
            "commit" => "def456newsha", "product_version" => "0.5.0",
            "url" => "https://x/z.zip", "installable" => nil
          } })
          ENV["LEVELCODE_UPDATE_FEED_SIGNED"] = "1"
        end

        it "reads null as NOT installable — 204 to Squirrel, never the installable default" do
          get UPDATE_URL, headers: { "User-Agent" => "LevelCode/0.5.0 Squirrel/1.0" }
          expect(response).to have_http_status(:no_content)
        end

        it "still announces to the notify-only extension" do
          get UPDATE_URL, headers: NOTIFY_UA
          expect(response).to have_http_status(:ok)
        end
      end
    end

    context "GitHub-Releases fallback — no env feed configured" do
      before do
        allow(Levelcode::EditorReleaseFeed).to receive(:latest)
          .with(target: "darwin-arm64", quality: "stable")
          .and_return(
            commit: "fd81887anewsha", product_version: "0.6.0",
            url: "https://github.com/levelcodeai/levelcode/releases/tag/v0.6.0",
            sha256hash: nil, timestamp: 1_784_231_903,
            release_notes_url: "https://github.com/levelcodeai/levelcode/releases/tag/v0.6.0"
          )
      end

      it "announces the release straight from GitHub — publishing a release IS the announcement" do
        get UPDATE_URL, headers: NOTIFY_UA
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["version"]).to eq("fd81887anewsha")
        expect(body["productVersion"]).to eq("0.6.0")
        expect(body["url"]).to eq("https://github.com/levelcodeai/levelcode/releases/tag/v0.6.0")
      end

      it "the env feed WINS over the GitHub fallback when both exist (the manual pin)" do
        set_feed("darwin-arm64" => { "stable" => {
          "commit" => "pinnedsha", "product_version" => "0.6.1", "url" => "https://x/pinned.zip"
        } })
        get UPDATE_URL, headers: NOTIFY_UA
        expect(response.parsed_body["version"]).to eq("pinnedsha")
      end

      it "returns 204 when the running build IS the GitHub latest" do
        get "/api/update/darwin-arm64/stable/fd81887anewsha", headers: NOTIFY_UA
        expect(response).to have_http_status(:no_content)
      end
    end

    context "when nothing is published for the requested target" do
      before { set_feed("win32-x64" => { "stable" => { "commit" => "zzz" } }) }

      it "returns 204 (darwin-arm64 has no entry)" do
        get UPDATE_URL
        expect(response).to have_http_status(:no_content)
      end
    end

    context "FAIL-SAFE — malformed feed must never 5xx or return HTML" do
      before { ENV["LEVELCODE_UPDATE_FEED"] = "{not valid json" }

      it "returns 204, not 500 or an HTML error page" do
        get UPDATE_URL
        expect(response).to have_http_status(:no_content)
        expect(response.content_type.to_s).not_to include("text/html")
      end
    end

    context "FAIL-SAFE — an INCOMPLETE feed entry is treated as unpublished (never a 200 with null fields)" do
      it "returns 204 when the entry is missing url" do
        set_feed("darwin-arm64" => { "stable" => { "commit" => "def456newsha", "product_version" => "0.5.0" } })
        get UPDATE_URL
        expect(response).to have_http_status(:no_content)
      end

      it "returns 204 when the entry is missing product_version" do
        set_feed("darwin-arm64" => { "stable" => { "commit" => "def456newsha", "url" => "https://x/z.zip" } })
        get UPDATE_URL
        expect(response).to have_http_status(:no_content)
      end
    end

    context "FAIL-SAFE — valid JSON that isn't an object (null / array / scalar)" do
      it "returns 204 deterministically, without hitting the exception rescue path" do
        allow(Rails.logger).to receive(:warn)
        ENV["LEVELCODE_UPDATE_FEED"] = "null"
        get UPDATE_URL
        expect(response).to have_http_status(:no_content)
        expect(Rails.logger).not_to have_received(:warn).with(/Api::Updates/)
      end

      it "returns 204 for a JSON array too" do
        ENV["LEVELCODE_UPDATE_FEED"] = "[]"
        get UPDATE_URL
        expect(response).to have_http_status(:no_content)
      end
    end
  end
end
