require "rails_helper"

RSpec.describe LinkLifecycleManagerJob, type: :job do
  let(:user) { create(:user) }

  before do
    Sidekiq::Testing.inline!
  end

  describe "#perform" do
    context "auto-activation" do
      it "activates draft links whose activates_at has passed" do
        link = create(:link, user: user, state: "draft", governance_enabled: true, activates_at: 1.hour.ago)

        LinkLifecycleManagerJob.new.perform

        expect(link.reload.state).to eq("active")
      end

      it "does not activate draft links whose activates_at is in the future" do
        link = create(:link, user: user, state: "draft", governance_enabled: true, activates_at: 1.hour.from_now)

        LinkLifecycleManagerJob.new.perform

        expect(link.reload.state).to eq("draft")
      end

      it "does not activate non-governed links" do
        link = create(:link, user: user, state: "draft", governance_enabled: false, activates_at: 1.hour.ago)

        LinkLifecycleManagerJob.new.perform

        expect(link.reload.state).to eq("draft")
      end
    end

    context "auto-expiration by time" do
      it "expires active links whose expires_at has passed" do
        link = create(:link, user: user, state: "active", governance_enabled: true, expires_at: 1.hour.ago)

        LinkLifecycleManagerJob.new.perform

        expect(link.reload.state).to eq("expired")
      end

      it "does not expire links whose expires_at is in the future" do
        link = create(:link, user: user, state: "active", governance_enabled: true, expires_at: 1.hour.from_now)

        LinkLifecycleManagerJob.new.perform

        expect(link.reload.state).to eq("active")
      end
    end

    context "auto-expiration by click cap" do
      it "expires active links that reached their click cap" do
        link = create(:link, user: user, state: "active", governance_enabled: true, click_cap: 10)
        link.update_column(:clicks_count, 10)

        LinkLifecycleManagerJob.new.perform

        expect(link.reload.state).to eq("expired")
      end

      it "does not expire links under their click cap" do
        link = create(:link, user: user, state: "active", governance_enabled: true, click_cap: 10)
        link.update_column(:clicks_count, 5)

        LinkLifecycleManagerJob.new.perform

        expect(link.reload.state).to eq("active")
      end
    end

    it "creates audit log entries for auto-transitions" do
      create(:link, user: user, state: "active", governance_enabled: true, expires_at: 1.hour.ago)

      expect {
        LinkLifecycleManagerJob.new.perform
      }.to change(LinkGovernanceLog, :count).by(1)

      log = LinkGovernanceLog.last
      expect(log.action).to eq("state_change")
      expect(log.reason).to include("Auto-expired")
    end
  end
end
