require "rails_helper"

RSpec.describe "Link Governance API", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }
  let(:link) { create(:link, user: user, governance_enabled: true) }

  describe "PATCH /api/v1/links/:lookup_code/governance/transition" do
    it "transitions a link state" do
      patch "/api/v1/links/#{link.lookup_code}/governance/transition",
            params: { state: "paused", reason: "Maintenance" },
            headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["state"]).to eq("paused")
      expect(link.reload.state).to eq("paused")
    end

    it "returns 422 for invalid state" do
      patch "/api/v1/links/#{link.lookup_code}/governance/transition",
            params: { state: "invalid" },
            headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "creates an audit log entry" do
      expect {
        patch "/api/v1/links/#{link.lookup_code}/governance/transition",
              params: { state: "paused", reason: "Test" },
              headers: headers
      }.to change(LinkGovernanceLog, :count).by(1)
    end

    it "returns 401 for unauthenticated requests" do
      patch "/api/v1/links/#{link.lookup_code}/governance/transition",
            params: { state: "paused" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 for another user's link" do
      other_user = create(:user)
      other_headers = auth_headers(other_user)

      patch "/api/v1/links/#{link.lookup_code}/governance/transition",
            params: { state: "paused" },
            headers: other_headers

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/links/:lookup_code/governance/destination" do
    it "updates the destination URL" do
      patch "/api/v1/links/#{link.lookup_code}/governance/destination",
            params: { destination_url: "https://new.example.com", reason: "Campaign update" },
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(link.reload.original_url).to eq("https://new.example.com")
    end

    it "creates a destination history entry" do
      initial_count = link.destination_histories.count

      patch "/api/v1/links/#{link.lookup_code}/governance/destination",
            params: { destination_url: "https://new.example.com" },
            headers: headers

      expect(link.destination_histories.count).to be > initial_count
    end
  end

  describe "GET /api/v1/links/:lookup_code/governance/audit_log" do
    before do
      link.transition_to!("paused", user: user, reason: "Test")
      link.transition_to!("active", user: user, reason: "Resume")
    end

    it "returns the audit log" do
      get "/api/v1/links/#{link.lookup_code}/governance/audit_log", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["logs"].length).to eq(2)
      expect(json["logs"].first["action"]).to eq("state_change")
    end
  end

  describe "GET /api/v1/links/:lookup_code/governance/destination_history" do
    before do
      link.update_destination!("https://v1.example.com", user: user)
      link.update_destination!("https://v2.example.com", user: user)
    end

    it "returns destination history" do
      get "/api/v1/links/#{link.lookup_code}/governance/destination_history", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["histories"].length).to be >= 2
    end
  end

  describe "POST /api/v1/links/governance/pause_all" do
    it "pauses all active governed links for current user" do
      active_governed = create_list(:link, 2, user: user, governance_enabled: true, state: "active")
      create(:link, user: user, governance_enabled: true, state: "paused")
      create(:link, user: user, governance_enabled: false, state: "active")

      post "/api/v1/links/governance/pause_all",
           params: { reason: "Emergency stop" },
           headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["paused_count"]).to eq(2)
      expect(json["paused_lookup_codes"].sort).to eq(active_governed.map(&:lookup_code).sort)
      expect(active_governed.all? { |l| l.reload.state == "paused" }).to eq(true)
    end

    it "returns 401 for unauthenticated requests" do
      post "/api/v1/links/governance/pause_all", params: { reason: "Maintenance" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

RSpec.describe "Routing Rules API", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }
  let(:link) { create(:link, user: user, governance_enabled: true) }

  describe "GET /api/v1/links/:lookup_code/routing_rules" do
    it "lists all routing rules for a link" do
      create(:link_routing_rule, link: link)

      get "/api/v1/links/#{link.lookup_code}/routing_rules", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["rules"].length).to eq(1)
    end
  end

  describe "POST /api/v1/links/:lookup_code/routing_rules" do
    it "creates a routing rule" do
      params = {
        routing_rule: {
          rule_type: "geo",
          conditions: { countries: [ "US" ] },
          destination_url: "https://us.example.com",
          priority: 1
        }
      }

      post "/api/v1/links/#{link.lookup_code}/routing_rules",
           params: params, headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["rule_type"]).to eq("geo")
    end

    it "creates an audit log entry" do
      params = {
        routing_rule: {
          rule_type: "device",
          conditions: { device_types: [ "mobile" ] },
          destination_url: "https://m.example.com",
          priority: 1
        }
      }

      expect {
        post "/api/v1/links/#{link.lookup_code}/routing_rules",
             params: params, headers: headers
      }.to change(LinkGovernanceLog, :count).by(1)
    end

    it "returns 422 for invalid rule" do
      params = { routing_rule: { rule_type: "invalid", destination_url: "https://example.com" } }

      post "/api/v1/links/#{link.lookup_code}/routing_rules",
           params: params, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/links/:lookup_code/routing_rules/:id" do
    let!(:rule) { create(:link_routing_rule, link: link) }

    it "updates a routing rule" do
      patch "/api/v1/links/#{link.lookup_code}/routing_rules/#{rule.id}",
            params: { routing_rule: { destination_url: "https://updated.example.com" } },
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(rule.reload.destination_url).to eq("https://updated.example.com")
    end
  end

  describe "DELETE /api/v1/links/:lookup_code/routing_rules/:id" do
    let!(:rule) { create(:link_routing_rule, link: link) }

    it "deletes a routing rule" do
      expect {
        delete "/api/v1/links/#{link.lookup_code}/routing_rules/#{rule.id}",
               headers: headers
      }.to change(LinkRoutingRule, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end

RSpec.describe "Campaigns API", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }

  describe "GET /api/v1/campaigns" do
    it "lists all campaigns for the current user" do
      campaign = create(:link_campaign, user: user, name: "Summer Sale")
      create(:link_campaign, user: user, name: "Winter Promo")
      link = create(:link, user: user, link_campaign: campaign, clicks_count: 12, title: "Docs")

      get "/api/v1/campaigns", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["campaigns"].length).to eq(2)
      summer_sale = json["campaigns"].find { |item| item["id"] == campaign.id }
      expect(summer_sale["total_clicks"]).to eq(12)
      expect(summer_sale["links"]).to include(
        a_hash_including(
          "id" => link.id,
          "lookup_code" => link.lookup_code,
          "title" => "Docs",
          "clicks_count" => 12
        )
      )
    end
  end

  describe "POST /api/v1/campaigns" do
    it "creates a campaign" do
      post "/api/v1/campaigns",
           params: { campaign: { name: "Black Friday", description: "Annual sale" } },
           headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["name"]).to eq("Black Friday")
    end
  end

  describe "POST /api/v1/campaigns/:id/pause" do
    it "pauses all links in the campaign" do
      campaign = create(:link_campaign, user: user)
      link = create(:link, user: user, link_campaign: campaign, governance_enabled: true)

      post "/api/v1/campaigns/#{campaign.id}/pause",
           params: { reason: "Budget cap reached" },
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(link.reload.state).to eq("paused")
    end
  end

  describe "POST /api/v1/campaigns/:id/resume" do
    it "resumes all links in the campaign" do
      campaign = create(:link_campaign, user: user, state: "paused")
      link = create(:link, user: user, link_campaign: campaign, state: "paused", governance_enabled: true)

      post "/api/v1/campaigns/#{campaign.id}/resume", headers: headers

      expect(response).to have_http_status(:ok)
      expect(link.reload.state).to eq("active")
    end
  end

  describe "DELETE /api/v1/campaigns/:id" do
    it "deletes a campaign and nullifies links" do
      campaign = create(:link_campaign, user: user)
      link = create(:link, user: user, link_campaign: campaign)

      delete "/api/v1/campaigns/#{campaign.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(link.reload.link_campaign_id).to be_nil
    end
  end
end
