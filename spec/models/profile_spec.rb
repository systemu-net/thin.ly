# == Schema Information
#
# Table name: profiles
#
#  id              :bigint           not null, primary key
#  accent          :string           default("violet"), not null
#  bio             :text
#  display_name    :string
#  followers_count :integer          default(0), not null
#  following_count :integer          default(0), not null
#  handle          :string           not null
#  location        :string
#  privacy         :jsonb            not null
#  published_at    :datetime
#  social_order    :jsonb            not null
#  socials         :jsonb            not null
#  verified        :boolean          default(FALSE), not null
#  website         :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_profiles_on_lower_handle  (lower((handle)::text)) UNIQUE
#  index_profiles_on_user_id       (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require 'rails_helper'

RSpec.describe Profile, type: :model do
  describe "factory" do
    it "is valid" do
      expect(build(:profile)).to be_valid
    end
  end

  describe "handle validation & normalization" do
    it "requires a handle" do
      profile = build(:profile, handle: nil)
      expect(profile).not_to be_valid
    end

    it "rejects illegal characters" do
      expect(build(:profile, handle: "Has Space")).not_to be_valid
      expect(build(:profile, handle: "no!bang")).not_to be_valid
    end

    it "enforces length bounds" do
      expect(build(:profile, handle: "a")).not_to be_valid
      expect(build(:profile, handle: "a" * 31)).not_to be_valid
    end

    it "rejects reserved handles (routes, roles, RFC mailboxes, brands)" do
      %w[admin support billing postmaster api null google paypal instagram linktree anthropic thinly].each do |reserved|
        profile = build(:profile, handle: reserved)
        expect(profile).not_to be_valid, "expected '#{reserved}' to be reserved"
        expect(profile.errors[:handle]).to include("is reserved")
      end
    end

    it "loads a substantial blocklist from config/reserved_handles.txt" do
      expect(Profile::RESERVED_HANDLES.size).to be > 800
      expect(Profile::RESERVED_HANDLES).to be_a(Set)
    end

    it "is unique case-insensitively" do
      create(:profile, handle: "alexrivera")
      dup = build(:profile, handle: "AlexRivera")
      expect(dup).not_to be_valid
    end

    it "normalizes to lowercase and strips a leading @" do
      profile = build(:profile, handle: " @MixedCase ")
      profile.valid?
      expect(profile.handle).to eq("mixedcase")
    end
  end

  describe "other validations" do
    it "limits bio to 160 chars" do
      expect(build(:profile, bio: "x" * 161)).not_to be_valid
      expect(build(:profile, bio: "x" * 160)).to be_valid
    end

    it "only allows known accents" do
      expect(build(:profile, accent: "neon")).not_to be_valid
      expect(build(:profile, accent: "mint")).to be_valid
    end
  end

  describe "privacy predicates" do
    it "reads flags from the privacy jsonb with sensible defaults" do
      profile = build(:profile)
      expect(profile.is_public?).to be(true)
      expect(profile.allow_messages?).to be(false)

      profile.privacy = { "is_public" => false, "allow_messages" => true }
      expect(profile.is_public?).to be(false)
      expect(profile.allow_messages?).to be(true)
    end
  end

  describe ".find_by_handle" do
    it "matches case-insensitively and tolerates a leading @" do
      profile = create(:profile, handle: "alexrivera")
      expect(Profile.find_by_handle("AlexRivera")).to eq(profile)
      expect(Profile.find_by_handle("@alexrivera")).to eq(profile)
      expect(Profile.find_by_handle("nope")).to be_nil
    end
  end

  describe "#public_profile_links" do
    it "returns only visible + active links, pinned first then by position" do
      profile = create(:profile)
      user = profile.user

      active_a = create(:link, user: user, state: "active")
      active_b = create(:link, user: user, state: "active")
      paused   = create(:link, user: user, state: "paused")
      hidden   = create(:link, user: user, state: "active")
      pinned   = create(:link, user: user, state: "active")

      create(:profile_link, profile: profile, link: active_b, position: 2)
      create(:profile_link, profile: profile, link: active_a, position: 1)
      create(:profile_link, profile: profile, link: paused,   position: 0)
      create(:profile_link, profile: profile, link: hidden,   position: 0, visible: false)
      create(:profile_link, profile: profile, link: pinned,   position: 9, pinned: true)

      result = profile.public_profile_links.map(&:link)
      expect(result).to eq([ pinned, active_a, active_b ]) # pinned first, then position 1, 2
      expect(result).not_to include(paused, hidden)
    end
  end

  describe "User#create_default_profile" do
    it "auto-creates a profile with a unique handle on user creation" do
      u1 = create(:user)
      u2 = create(:user)
      expect(u1.profile).to be_present
      expect(u1.profile.handle).to be_present
      expect(u1.profile.handle).not_to eq(u2.profile.handle)
    end
  end
end
