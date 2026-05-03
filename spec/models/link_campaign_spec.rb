# == Schema Information
#
# Table name: link_campaigns
#
#  id           :bigint           not null, primary key
#  accent_color :string           default("#7c3aed"), not null
#  description  :text
#  name         :string           not null
#  state        :string           default("active"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_link_campaigns_on_accent_color  (accent_color)
#  index_link_campaigns_on_user_id       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe LinkCampaign, type: :model do
  let(:user) { create(:user) }

  describe "validations" do
    it "requires a name" do
      campaign = build(:link_campaign, user: user, name: nil)
      expect(campaign).not_to be_valid
    end

    it "validates state inclusion" do
      campaign = build(:link_campaign, user: user, state: "invalid")
      expect(campaign).not_to be_valid
    end

    it "allows valid states" do
      %w[active paused archived].each do |state|
        campaign = build(:link_campaign, user: user, state: state)
        expect(campaign).to be_valid
      end
    end
  end

  describe "#pause_all!" do
    it "pauses all links in the campaign" do
      campaign = create(:link_campaign, user: user)
      link1 = create(:link, user: user, link_campaign: campaign, governance_enabled: true)
      link2 = create(:link, user: user, link_campaign: campaign, governance_enabled: true)

      campaign.pause_all!(user: user)

      expect(link1.reload.state).to eq("paused")
      expect(link2.reload.state).to eq("paused")
      expect(campaign.reload.state).to eq("paused")
    end
  end

  describe "#resume_all!" do
    it "resumes all paused links in the campaign" do
      campaign = create(:link_campaign, user: user, state: "paused")
      link = create(:link, user: user, link_campaign: campaign, state: "paused", governance_enabled: true)

      campaign.resume_all!(user: user)

      expect(link.reload.state).to eq("active")
      expect(campaign.reload.state).to eq("active")
    end
  end

  describe "#expire_all!" do
    it "expires all links in the campaign" do
      campaign = create(:link_campaign, user: user)
      link = create(:link, user: user, link_campaign: campaign, governance_enabled: true)

      campaign.expire_all!(user: user)

      expect(link.reload.state).to eq("expired")
      expect(campaign.reload.state).to eq("expired")
    end
  end

  describe "associations" do
    it "has many links" do
      campaign = create(:link_campaign, user: user)
      create(:link, user: user, link_campaign: campaign)
      expect(campaign.links.count).to eq(1)
    end

    it "nullifies link_campaign_id on destroy" do
      campaign = create(:link_campaign, user: user)
      link = create(:link, user: user, link_campaign: campaign)
      campaign.destroy
      expect(link.reload.link_campaign_id).to be_nil
    end
  end
end
