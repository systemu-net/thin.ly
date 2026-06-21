require 'rails_helper'

RSpec.describe "Api::V1::PublicProfiles", type: :request do
  let(:user) { create(:user) }
  let(:profile) { user.profile }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test123'))
    profile.update!(handle: "alexrivera", display_name: "Alex Rivera", bio: "Designer")
  end

  def curate(link, **attrs)
    create(:profile_link, { profile: profile, link: link }.merge(attrs))
  end

  describe "GET /api/v1/profiles/:handle (public)" do
    it "returns the public profile with only visible + active links" do
      active = create(:link, user: user, state: "active", title: "My site")
      pinned = create(:link, user: user, state: "active", title: "Pinned")
      paused = create(:link, user: user, state: "paused")
      hidden = create(:link, user: user, state: "active")
      curate(active, position: 1)
      curate(pinned, position: 5, pinned: true)
      curate(paused, position: 2)
      curate(hidden, position: 3, visible: false)

      get "/api/v1/profiles/alexrivera"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["handle"]).to eq("alexrivera")
      expect(json["private"]).to be(false)
      expect(json["is_owner"]).to be(false)

      titles = json["links"].map { |l| l["title"] }
      expect(titles).to eq([ "Pinned", "My site" ]) # pinned first, then position
      expect(json["links"].first).to include("pinned" => true, "state" => "active")
      expect(json["links"].first["spark"].length).to eq(7)
    end

    it "handles dotted handles" do
      profile.update!(handle: "sergii.demianchuk")
      get "/api/v1/profiles/sergii.demianchuk"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["handle"]).to eq("sergii.demianchuk")
    end

    it "404s for an unknown handle" do
      get "/api/v1/profiles/ghost"
      expect(response).to have_http_status(:not_found)
    end

    it "reflects per-link click sparklines" do
      link = create(:link, user: user, state: "active")
      curate(link, position: 1)
      create_list(:click, 3, link: link, created_at: 1.day.ago)

      get "/api/v1/profiles/alexrivera"
      spark = JSON.parse(response.body)["links"].first["spark"]
      expect(spark.sum).to eq(3)
    end

    context "privacy" do
      it "returns a placeholder for a private profile and hides content" do
        profile.update!(privacy: profile.privacy.merge("is_public" => false))
        link = create(:link, user: user, state: "active")
        curate(link, position: 1)

        get "/api/v1/profiles/alexrivera"
        json = JSON.parse(response.body)
        expect(json["private"]).to be(true)
        expect(json).not_to have_key("links")
        expect(json).not_to have_key("bio")
      end

      it "omits follower count when show_followers is off" do
        profile.update!(privacy: profile.privacy.merge("show_followers" => false))
        get "/api/v1/profiles/alexrivera"
        expect(JSON.parse(response.body)["followers_count"]).to be_nil
      end
    end

    context "when the owner is authenticated" do
      it "sets is_owner true" do
        sign_in user
        get "/api/v1/profiles/alexrivera", headers: auth_headers(user)
        expect(JSON.parse(response.body)["is_owner"]).to be(true)
      end
    end
  end
end
