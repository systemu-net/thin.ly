require "rails_helper"

# The LevelCode editor update feed (Code-OSS contract). See Api::UpdatesController.
RSpec.describe "Api::Updates", type: :request do
  UPDATE_URL = "/api/update/darwin-arm64/stable/abc123runningsha".freeze

  after { ENV.delete("LEVELCODE_UPDATE_FEED") }

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

      it "returns 200 JSON in the exact Code-OSS feed shape" do
        get UPDATE_URL
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
        get UPDATE_URL
        expect(response.parsed_body["releaseNotesUrl"]).to eq("https://github.com/levelcodeai/levelcode/releases/latest")
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
  end
end
