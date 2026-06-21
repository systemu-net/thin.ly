require 'rails_helper'

RSpec.describe "Api::V1::Profile (owner)", type: :request do
  let(:user) { create(:user) }
  let(:profile) { user.profile }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test123'))
  end

  describe "GET /api/v1/profile" do
    it "requires authentication" do
      get "/api/v1/profile"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the current user's profile with owner fields" do
      sign_in user
      get "/api/v1/profile", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["handle"]).to eq(profile.handle)
      expect(json["is_owner"]).to be(true)
      expect(json["privacy"]).to include("is_public" => true, "allow_messages" => false)
      expect(json).to have_key("followers_count")
      expect(json["public_url"]).to include("/@#{profile.handle}")
    end
  end

  describe "PATCH /api/v1/profile" do
    before { sign_in user }

    it "updates identity, accent and bio" do
      patch "/api/v1/profile",
        params: { profile: { display_name: "Alex Rivera", bio: "Designer", accent: "mint" } }.to_json,
        headers: auth_headers(user).merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(profile.reload.display_name).to eq("Alex Rivera")
      expect(profile.accent).to eq("mint")
    end

    it "merges socials partially without wiping existing keys" do
      profile.update!(socials: { "instagram" => "alex" })
      patch "/api/v1/profile",
        params: { profile: { socials: { youtube: "alextube" } } }.to_json,
        headers: auth_headers(user).merge("Content-Type" => "application/json")

      expect(profile.reload.socials).to eq("instagram" => "alex", "youtube" => "alextube")
    end

    it "merges and casts privacy flags" do
      patch "/api/v1/profile",
        params: { profile: { privacy: { is_public: false } } }.to_json,
        headers: auth_headers(user).merge("Content-Type" => "application/json")

      expect(profile.reload.is_public?).to be(false)
      expect(profile.show_followers?).to be(true) # untouched flag preserved
    end

    it "rejects a reserved handle" do
      patch "/api/v1/profile",
        params: { profile: { handle: "admin" } }.to_json,
        headers: auth_headers(user).merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"].join).to match(/reserved/)
    end

    it "rejects an invalid accent" do
      patch "/api/v1/profile",
        params: { profile: { accent: "neon" } }.to_json,
        headers: auth_headers(user).merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /api/v1/profile/publish" do
    before { sign_in user }

    it "stamps published_at and marks the profile live" do
      expect(profile.published?).to be(false)
      post "/api/v1/profile/publish", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["published"]).to be(true)
      expect(json["published_at"]).to be_present
      expect(profile.reload.published?).to be(true)
    end
  end

  describe "GET /api/v1/handles/check" do
    before { sign_in user }

    def check(handle)
      get "/api/v1/handles/check", params: { handle: handle }, headers: auth_headers(user)
      JSON.parse(response.body)
    end

    it "reports an available handle" do
      expect(check("totally_free_handle")).to include("available" => true)
    end

    it "treats the owner's current handle as available" do
      expect(check(profile.handle)).to include("available" => true)
    end

    it "rejects reserved, taken, too-short and invalid handles" do
      other = create(:user)
      other.profile.update!(handle: "takenhandle")

      expect(check("admin")).to include("available" => false, "reason" => "reserved")
      expect(check("takenhandle")).to include("available" => false, "reason" => "taken")
      expect(check("a")).to include("available" => false, "reason" => "too_short")
      expect(check("bad space")).to include("available" => false, "reason" => "invalid")
    end
  end
end
