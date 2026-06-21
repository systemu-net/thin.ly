# == Schema Information
#
# Table name: profile_links
#
#  id             :bigint           not null, primary key
#  pinned         :boolean          default(FALSE), not null
#  position       :integer          default(0), not null
#  tag            :string
#  title_override :string
#  visible        :boolean          default(TRUE), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  link_id        :bigint           not null
#  profile_id     :bigint           not null
#
# Indexes
#
#  index_profile_links_on_link_id                  (link_id)
#  index_profile_links_on_profile_id               (profile_id)
#  index_profile_links_on_profile_id_and_link_id   (profile_id,link_id) UNIQUE
#  index_profile_links_on_profile_id_and_position  (profile_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (link_id => links.id)
#  fk_rails_...  (profile_id => profiles.id)
#
require 'rails_helper'

RSpec.describe ProfileLink, type: :model do
  it "has a valid factory" do
    expect(build(:profile_link)).to be_valid
  end

  it "is unique per (profile, link)" do
    pl = create(:profile_link)
    dup = build(:profile_link, profile: pl.profile, link: pl.link)
    expect(dup).not_to be_valid
    expect(dup.errors[:link_id]).to be_present
  end

  it "rejects a link owned by another user" do
    profile = create(:profile)
    other_link = create(:link, user: create(:user))
    pl = build(:profile_link, profile: profile, link: other_link)
    expect(pl).not_to be_valid
    expect(pl.errors[:link]).to be_present
  end

  describe "#display_title" do
    it "prefers override, then link title, then slug" do
      profile = create(:profile)
      link = create(:link, user: profile.user, title: nil)
      pl = create(:profile_link, profile: profile, link: link)

      expect(pl.display_title).to eq(link.lookup_code)

      link.update!(title: "Link Title")
      expect(pl.display_title).to eq("Link Title")

      pl.update!(title_override: "Override")
      expect(pl.display_title).to eq("Override")
    end
  end
end
