require "rails_helper"

RSpec.describe "LinkGovernance concern", type: :model do
  let(:user) { create(:user) }
  let(:link) { create(:link, user: user) }

  describe "state validations" do
    it "allows valid states" do
      %w[draft active paused expired archived].each do |state|
        link.state = state
        expect(link).to be_valid
      end
    end

    it "rejects invalid states" do
      link.state = "destroyed"
      expect(link).not_to be_valid
    end
  end

  describe "#transition_to!" do
    it "changes the link state" do
      link.transition_to!("paused", user: user, reason: "Manual pause")
      expect(link.reload.state).to eq("paused")
    end

    it "creates a governance log entry" do
      expect {
        link.transition_to!("paused", user: user, reason: "Manual pause")
      }.to change(LinkGovernanceLog, :count).by(1)

      log = LinkGovernanceLog.last
      expect(log.action).to eq("state_change")
      expect(log.before_state).to eq({ "state" => "active" })
      expect(log.after_state).to eq({ "state" => "paused" })
      expect(log.reason).to eq("Manual pause")
      expect(log.user).to eq(user)
    end

    it "raises ArgumentError for invalid state" do
      expect {
        link.transition_to!("invalid")
      }.to raise_error(ArgumentError, "Invalid state: invalid")
    end

    it "records ip_address when provided" do
      link.transition_to!("paused", user: user, ip_address: "192.168.1.1")
      expect(LinkGovernanceLog.last.ip_address).to eq("192.168.1.1")
    end
  end

  describe "#update_destination!" do
    let(:link) { create(:link, user: user, governance_enabled: true) }

    it "changes the original_url" do
      link.update_destination!("https://new.example.com", user: user, reason: "Campaign update")
      expect(link.reload.original_url).to eq("https://new.example.com")
    end

    it "creates a governance log entry" do
      old_url = link.original_url
      link.update_destination!("https://new.example.com", user: user, reason: "Campaign update")

      log = link.governance_logs.where(action: "destination_update").last
      expect(log.before_state).to eq({ "destination_url" => old_url })
      expect(log.after_state).to eq({ "destination_url" => "https://new.example.com" })
    end

    it "creates a destination history entry" do
      # The governed link already has 1 initial history from record_initial_destination
      expect(link.destination_histories.count).to eq(1)

      link.update_destination!("https://new.example.com", user: user)

      history = link.destination_histories.order(:created_at).last
      expect(history.destination_url).to eq("https://new.example.com")
      expect(history.active_from).to be_present
    end

    it "closes previous destination history" do
      link.update_destination!("https://first.example.com", user: user)
      first_history = link.destination_histories.last

      link.update_destination!("https://second.example.com", user: user)
      expect(first_history.reload.active_until).to be_present
    end
  end

  describe "#resolve_destination" do
    it "returns original_url for non-governed active links" do
      expect(link.resolve_destination).to eq(link.original_url)
    end

    it "returns paused_redirect_url when paused" do
      link.update!(state: "paused", governance_enabled: true, paused_redirect_url: "https://paused.example.com")
      expect(link.resolve_destination).to eq("https://paused.example.com")
    end

    it "returns nil when paused with no fallback" do
      link.update!(state: "paused", governance_enabled: true)
      expect(link.resolve_destination).to be_nil
    end

    it "returns expired_redirect_url when expired" do
      link.update!(state: "expired", governance_enabled: true, expired_redirect_url: "https://expired.example.com")
      expect(link.resolve_destination).to eq("https://expired.example.com")
    end

    it "returns expired_redirect_url when click_cap reached" do
      link.update!(
        governance_enabled: true,
        click_cap: 5,
        clicks_count: 5,
        expired_redirect_url: "https://limit.example.com"
      )
      expect(link.resolve_destination).to eq("https://limit.example.com")
    end

    it "returns expired_redirect_url when expires_at is past" do
      link.update!(
        governance_enabled: true,
        expires_at: 1.hour.ago,
        expired_redirect_url: "https://expired.example.com"
      )
      expect(link.resolve_destination).to eq("https://expired.example.com")
    end

    context "with routing rules" do
      let(:governed_link) { create(:link, user: user, governance_enabled: true) }

      it "applies geo routing rules" do
        create(:link_routing_rule, link: governed_link, rule_type: "geo",
               conditions: { "countries" => [ "US" ] }, destination_url: "https://us.example.com")

        result = governed_link.resolve_destination(country: "US")
        expect(result).to eq("https://us.example.com")
      end

      it "falls back to original_url when no rules match" do
        create(:link_routing_rule, link: governed_link, rule_type: "geo",
               conditions: { "countries" => [ "JP" ] }, destination_url: "https://jp.example.com")

        result = governed_link.resolve_destination(country: "US")
        expect(result).to eq(governed_link.original_url)
      end

      it "applies device routing rules" do
        create(:link_routing_rule, :device, link: governed_link)
        result = governed_link.resolve_destination(device_type: "mobile")
        expect(result).to eq("https://m.example.com")
      end
    end
  end

  describe "scopes" do
    it ".active_now returns active links without past activation times" do
      active = create(:link, user: user, state: "active")
      create(:link, user: user, state: "paused")
      create(:link, user: user, state: "active", activates_at: 1.hour.from_now)

      expect(Link.active_now).to include(active)
      expect(Link.active_now.count).to eq(1)
    end

    it ".expiring_soon returns links expiring within 24 hours" do
      expiring = create(:link, user: user, state: "active", expires_at: 12.hours.from_now)
      create(:link, user: user, state: "active", expires_at: 3.days.from_now)
      create(:link, user: user, state: "active") # no expiry

      expect(Link.expiring_soon).to include(expiring)
      expect(Link.expiring_soon.count).to eq(1)
    end

    it ".governed returns only governance_enabled links" do
      governed = create(:link, user: user, governance_enabled: true)
      create(:link, user: user, governance_enabled: false)

      expect(Link.governed).to eq([ governed ])
    end
  end

  describe "state predicates" do
    it "responds to state predicates" do
      link.state = "draft"
      expect(link).to be_draft

      link.state = "active"
      expect(link).to be_active

      link.state = "paused"
      expect(link).to be_paused

      link.state = "expired"
      expect(link).to be_expired

      link.state = "archived"
      expect(link).to be_archived
    end
  end

  describe "#expired_or_over_cap?" do
    it "returns true when state is expired" do
      link.state = "expired"
      expect(link.expired_or_over_cap?).to be true
    end

    it "returns true when expires_at has passed" do
      link.expires_at = 1.hour.ago
      expect(link.expired_or_over_cap?).to be true
    end

    it "returns true when click_cap is reached" do
      link.click_cap = 10
      link.clicks_count = 10
      expect(link.expired_or_over_cap?).to be true
    end

    it "returns false when none of the conditions are met" do
      expect(link.expired_or_over_cap?).to be false
    end
  end

  describe "associations" do
    it "belongs to a campaign" do
      campaign = create(:link_campaign, user: user)
      link.update!(link_campaign: campaign)
      expect(link.link_campaign).to eq(campaign)
    end

    it "has many routing_rules" do
      governed_link = create(:link, user: user, governance_enabled: true)
      rule = create(:link_routing_rule, link: governed_link)
      expect(governed_link.routing_rules).to include(rule)
    end

    it "has many governance_logs" do
      governed_link = create(:link, user: user, governance_enabled: true)
      governed_link.transition_to!("paused", user: user)
      expect(governed_link.governance_logs.count).to eq(1)
    end

    it "has many destination_histories" do
      governed_link = create(:link, user: user, governance_enabled: true)
      governed_link.update_destination!("https://new.example.com", user: user)
      expect(governed_link.destination_histories.count).to be >= 1
    end
  end
end
