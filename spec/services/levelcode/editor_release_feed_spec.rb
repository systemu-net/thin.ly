require "rails_helper"

# The GitHub-Releases-backed update-feed source. HTTP is stubbed at the `github_json` seam;
# the test cache store is :null_store, so Rails.cache.fetch executes the block every time.
RSpec.describe Levelcode::EditorReleaseFeed do
  RELEASE = {
    "tag_name" => "v0.6.0",
    "html_url" => "https://github.com/levelcodeai/levelcode/releases/tag/v0.6.0",
    "published_at" => "2026-07-16T20:38:23Z",
    "draft" => false,
    "prerelease" => false
  }.freeze

  def stub_github(release: RELEASE, sha: "fd81887a")
    allow(described_class).to receive(:github_json)
      .with("https://api.github.com/repos/levelcodeai/levelcode/releases/latest").and_return(release)
    allow(described_class).to receive(:github_json)
      .with("https://api.github.com/repos/levelcodeai/levelcode/commits/v0.6.0").and_return(sha && { "sha" => sha })
  end

  # A release carrying the signed Squirrel assets.
  def zip_asset(name, digest: "sha256:abc123")
    { "name" => name, "browser_download_url" => "https://github.com/dl/#{name}", "digest" => digest }
  end

  describe ".latest" do
    it "maps the latest release + tag commit to the feed-entry shape (v-prefix stripped, epoch timestamp)" do
      stub_github
      entry = described_class.latest(target: "darwin-arm64", quality: "stable")
      expect(entry).to eq(
        commit: "fd81887a",
        product_version: "0.6.0",
        # No signed .app.zip on this release → the release PAGE, and NOT installable: the notify-only
        # updater still announces it, but Squirrel must never be handed a web page to auto-install.
        url: "https://github.com/levelcodeai/levelcode/releases/tag/v0.6.0",
        sha256hash: nil,
        timestamp: Time.zone.parse("2026-07-16T20:38:23Z").to_i,
        release_notes_url: "https://github.com/levelcodeai/levelcode/releases/tag/v0.6.0",
        installable: false
      )
    end

    it "serves the arch-matched signed .app.zip (+ bare sha256) and marks it installable" do
      stub_github(release: RELEASE.merge("assets" => [
        zip_asset("LevelCode-arm64.app.zip"),
        zip_asset("LevelCode-x64.app.zip", digest: "sha256:def456"),
        { "name" => "LevelCode-arm64.dmg", "browser_download_url" => "https://github.com/dl/dmg" }
      ]))

      arm = described_class.latest(target: "darwin-arm64", quality: "stable")
      expect(arm).to include(url: "https://github.com/dl/LevelCode-arm64.app.zip",
                             sha256hash: "abc123", installable: true)

      intel = described_class.latest(target: "darwin", quality: "stable")
      expect(intel).to include(url: "https://github.com/dl/LevelCode-x64.app.zip",
                               sha256hash: "def456", installable: true)
    end

    it "NEVER serves a cross-arch zip: an arch with no asset falls back to the page, not installable" do
      stub_github(release: RELEASE.merge("assets" => [ zip_asset("LevelCode-arm64.app.zip") ]))

      intel = described_class.latest(target: "darwin", quality: "stable")
      expect(intel[:url]).to eq("https://github.com/levelcodeai/levelcode/releases/tag/v0.6.0")
      expect(intel[:installable]).to be(false)
      expect(intel[:url]).not_to include("arm64")
    end

    it "tolerates a missing digest (GitHub may omit it) — installable, hash nil" do
      stub_github(release: RELEASE.merge("assets" => [ zip_asset("LevelCode-arm64.app.zip", digest: nil) ]))
      entry = described_class.latest(target: "darwin-arm64", quality: "stable")
      expect(entry).to include(sha256hash: nil, installable: true)
    end

    it "serves both shipped macOS targets, and nothing else (no phantom announcements)" do
      stub_github
      expect(described_class.latest(target: "darwin", quality: "stable")).to be_present
      expect(described_class.latest(target: "win32-x64", quality: "stable")).to be_nil
      expect(described_class.latest(target: "darwin-arm64", quality: "insider")).to be_nil
    end

    it "short-circuits unknown targets WITHOUT calling GitHub" do
      expect(described_class).not_to receive(:github_json)
      described_class.latest(target: "linux-x64", quality: "stable")
    end

    it "ignores drafts and prereleases" do
      stub_github(release: RELEASE.merge("prerelease" => true))
      expect(described_class.latest(target: "darwin-arm64", quality: "stable")).to be_nil
    end

    it "returns nil when the tag can't be resolved to a commit" do
      stub_github(sha: nil)
      expect(described_class.latest(target: "darwin-arm64", quality: "stable")).to be_nil
    end

    it "FAIL-SAFE: any exception → nil (the controller's 204), logged, never raised" do
      allow(described_class).to receive(:github_json).and_raise(SocketError, "getaddrinfo")
      allow(Rails.logger).to receive(:warn)
      expect(described_class.latest(target: "darwin-arm64", quality: "stable")).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/EditorReleaseFeed.*SocketError/)
    end
  end
end
