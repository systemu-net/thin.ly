require 'rails_helper'

RSpec.describe "Api::V1::ProfileLinks (owner curation)", type: :request do
  let(:user) { create(:user) }
  let(:profile) { user.profile }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test123'))
  end

  def patch_links(items)
    patch "/api/v1/profile/links",
      params: { links: items }.to_json,
      headers: auth_headers(user).merge("Content-Type" => "application/json")
    JSON.parse(response.body)
  end

  describe "GET /api/v1/profile/links" do
    it "requires authentication" do
      get "/api/v1/profile/links"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns curated links and links available to add" do
      sign_in user
      curated = create(:link, user: user, title: "Curated")
      other   = create(:link, user: user, title: "Available")
      create(:profile_link, profile: profile, link: curated, position: 0)

      get "/api/v1/profile/links", headers: auth_headers(user)
      json = JSON.parse(response.body)

      expect(json["links"].map { |l| l["title"] }).to eq([ "Curated" ])
      expect(json["available_links"].map { |l| l["link_id"] }).to eq([ other.id ])
    end
  end

  describe "PATCH /api/v1/profile/links" do
    before { sign_in user }

    it "creates, orders and curates links from the payload" do
      l1 = create(:link, user: user)
      l2 = create(:link, user: user)

      json = patch_links([
        { link_id: l2.id, position: 0, pinned: true, tag: "new" },
        { link_id: l1.id, position: 1, visible: false }
      ])

      expect(response).to have_http_status(:ok)
      expect(profile.profile_links.count).to eq(2)
      first = json["links"].find { |l| l["link_id"] == l2.id }
      expect(first).to include("pinned" => true, "tag" => "new")
      second = json["links"].find { |l| l["link_id"] == l1.id }
      expect(second["visible"]).to be(false)
    end

    it "allows pinning multiple links" do
      l1 = create(:link, user: user)
      l2 = create(:link, user: user)
      json = patch_links([
        { link_id: l1.id, position: 0, pinned: true },
        { link_id: l2.id, position: 1, pinned: true }
      ])
      pinned = json["links"].select { |l| l["pinned"] }
      expect(pinned.length).to eq(2)
      expect(pinned.map { |l| l["link_id"] }).to contain_exactly(l1.id, l2.id)
    end

    it "removes links omitted from the payload" do
      l1 = create(:link, user: user)
      l2 = create(:link, user: user)
      create(:profile_link, profile: profile, link: l1, position: 0)
      create(:profile_link, profile: profile, link: l2, position: 1)

      patch_links([ { link_id: l1.id, position: 0 } ])
      expect(profile.reload.profile_links.map(&:link_id)).to eq([ l1.id ])
    end

    it "ignores links that belong to another user" do
      mine = create(:link, user: user)
      foreign = create(:link, user: create(:user))
      patch_links([
        { link_id: mine.id, position: 0 },
        { link_id: foreign.id, position: 1 }
      ])
      expect(profile.reload.profile_links.map(&:link_id)).to eq([ mine.id ])
    end
  end
end
