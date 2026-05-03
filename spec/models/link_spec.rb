# == Schema Information
#
# Table name: links
#
#  id                   :bigint           not null, primary key
#  activates_at         :datetime
#  click_cap            :integer
#  clicks_count         :integer          default(0), not null
#  description          :text
#  expired_redirect_url :string
#  expires_at           :datetime
#  governance_enabled   :boolean          default(FALSE), not null
#  is_safe              :boolean
#  last_scanned_at      :datetime
#  lookup_code          :string
#  original_url         :string
#  password_digest      :string
#  password_protected   :boolean          default(FALSE), not null
#  paused_redirect_url  :string
#  scan_failures        :integer          default(0)
#  state                :string           default("active"), not null
#  title                :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  link_campaign_id     :bigint
#  user_id              :bigint           not null
#
# Indexes
#
#  index_links_on_activates_at                 (activates_at)
#  index_links_on_expires_at                   (expires_at)
#  index_links_on_is_safe                      (is_safe)
#  index_links_on_is_safe_and_last_scanned_at  (is_safe,last_scanned_at)
#  index_links_on_last_scanned_at              (last_scanned_at)
#  index_links_on_link_campaign_id             (link_campaign_id)
#  index_links_on_state                        (state)
#  index_links_on_user_and_clicks_count        (user_id,clicks_count)
#  index_links_on_user_and_created             (user_id,created_at)
#  index_links_on_user_id                      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (link_campaign_id => link_campaigns.id)
#  fk_rails_...  (user_id => users.id)
#
require 'rails_helper'

RSpec.describe Link, type: :model do
  let(:user) { create(:user) }
  let(:stripe_customer_id) { '1234' }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: stripe_customer_id))
  end

  it 'always has an original URL' do
    link = Link.new(
      original_url: 'https://www.thin.ly/example',
      lookup_code: "1234567",
      user_id: user.id
    )
    expect { link.save }.to(change(Link, :count).by(1))
    expect(link.valid?).to eq(true)
  end

  it 'is invalid if the URL is not formatted properly' do
    link = Link.new(
      original_url: 'thin.ly/example'
    )
    expect(link.valid?).to eq(false)
  end

  it 'lookup_code is always not empty' do
    link = Link.new(
      original_url: 'https://www.thin.ly/example',
      lookup_code: nil,
      user_id: user.id
    )
    expect(link.valid?).to eq(true)
  end

  it 'is invalid if it does not have a original_url' do
    link = Link.new(
      original_url: nil,
      lookup_code: "1234567"
    )
    expect(link.valid?).to eq(false)
  end

  it 'is always generating new unique lookup_code for each record' do
    link = Link.new(
      original_url: 'https://www.thin.ly/example',
      lookup_code: "1234567",
      user_id: user.id
    )
    link.save
    link2 = Link.new(
      original_url: 'https://www.thin.ly/link2',
      lookup_code: "1234567",
      user_id: user.id
    )
    expect { link2.save }.to(change(Link, :count).by(1))
  end

  it 'returns the original URL and associated user_id for a given short link' do
    link = Link.new(original_url: 'https://www.thin.ly/example', user_id: user.id)
    link.save

    expect(link.send(:find_by_lookup_code, link.lookup_code)).to eq(link)
  end

  it 'fails to find the original URL for a given short link and wrong user_id' do
    link = Link.new(original_url: 'https://www.thin.ly/example', user_id: user.id)
    link.save

    expect(link.send(:find_by_lookup_code, link.lookup_code)).to eq(link)
  end

  describe 'sorting scopes' do
    let!(:old_link) { create(:link, user: user, created_at: 3.days.ago, clicks_count: 5) }
    let!(:middle_link) { create(:link, user: user, created_at: 2.days.ago, clicks_count: 10) }
    let!(:new_link) { create(:link, user: user, created_at: 1.day.ago, clicks_count: 3) }
    let!(:no_clicks_link) { create(:link, user: user, created_at: 4.days.ago, clicks_count: 0) }

    describe '.by_created_asc' do
      it 'sorts links by created_at in ascending order' do
        result = user.links.by_created_asc
        expect(result.pluck(:id)).to eq([ no_clicks_link.id, old_link.id, middle_link.id, new_link.id ])
      end
    end

    describe '.by_created_desc' do
      it 'sorts links by created_at in descending order' do
        result = user.links.by_created_desc
        expect(result.pluck(:id)).to eq([ new_link.id, middle_link.id, old_link.id, no_clicks_link.id ])
      end
    end

    describe '.by_clicks_asc' do
      it 'sorts links by clicks_count in ascending order' do
        result = user.links.by_clicks_asc
        expect(result.pluck(:id)).to eq([ no_clicks_link.id, new_link.id, old_link.id, middle_link.id ])
      end
    end

    describe '.by_clicks_desc' do
      it 'sorts links by clicks_count in descending order' do
        result = user.links.by_clicks_desc
        expect(result.pluck(:id)).to eq([ middle_link.id, old_link.id, new_link.id, no_clicks_link.id ])
      end
    end

    describe '.by_last_clicked_asc' do
      before do
        # Create clicks with different timestamps
        create(:click, link: old_link, created_at: 5.hours.ago)
        create(:click, link: middle_link, created_at: 2.hours.ago)
        create(:click, link: new_link, created_at: 1.hour.ago)
        # no_clicks_link has no clicks
      end

      it 'sorts links by last click timestamp in ascending order' do
        result = user.links.by_last_clicked_asc
        # Links with no clicks should appear first (NULLS FIRST)
        expect(result.first.id).to eq(no_clicks_link.id)
        # Then links ordered by oldest last click first
        expect(result.pluck(:id)[1..]).to eq([ old_link.id, middle_link.id, new_link.id ])
      end
    end

    describe '.by_last_clicked_desc' do
      before do
        # Create clicks with different timestamps
        create(:click, link: old_link, created_at: 5.hours.ago)
        create(:click, link: middle_link, created_at: 2.hours.ago)
        create(:click, link: new_link, created_at: 1.hour.ago)
        # no_clicks_link has no clicks
      end

      it 'sorts links by last click timestamp in descending order' do
        result = user.links.by_last_clicked_desc.to_a
        # Links ordered by most recent last click first
        expect(result[0..2].map(&:id)).to eq([ new_link.id, middle_link.id, old_link.id ])
        # Links with no clicks should appear last (NULLS LAST)
        expect(result.last.id).to eq(no_clicks_link.id)
      end
    end
  end
end
