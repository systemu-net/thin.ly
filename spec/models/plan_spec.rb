# == Schema Information
#
# Table name: plans
#
#  id              :bigint           not null, primary key
#  brand_pages     :integer
#  campaigns       :integer
#  links           :integer
#  name            :string           default("Free"), not null
#  qr_codes        :integer
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  subscription_id :bigint           not null
#
# Indexes
#
#  index_plans_on_subscription_id  (subscription_id)
#
# Foreign Keys
#
#  fk_rails_...  (subscription_id => subscriptions.id)
#
require 'rails_helper'

RSpec.describe Plan, type: :model do
  let(:user) { create(:user) }
  let(:plan) { user.plan }

  describe 'associations' do
    it 'belongs to a subscription' do
      expect(plan.subscription).to eq(user.subscriptions.first)
    end

    it 'has many api_requests' do
      assoc = described_class.reflect_on_association(:api_requests)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end
  end

  describe 'DEFAULT_PLAN' do
    it 'defines default plan limits' do
      expect(Plan::DEFAULT_PLAN).to eq({
        links: 50,
        qr_codes: 50,
        brand_pages: 1,
        campaigns: 1,
        name: "Free"
      })
    end
  end

  describe 'default plan creation' do
    it 'creates a Free plan with correct limits for new users' do
      expect(plan.name).to eq('Free')
      expect(plan.links).to eq(50)
      expect(plan.qr_codes).to eq(50)
      expect(plan.brand_pages).to eq(1)
    end
  end

  describe '#links_created_within_last_30_days' do
    it 'counts Link api_requests within the last 30 days' do
      link = create(:link, user: user)
      ApiRequest.create!(plan: plan, logable: link)
      ApiRequest.create!(plan: plan, logable: link)

      expect(plan.links_created_within_last_30_days).to eq(2)
    end

    it 'excludes requests older than 30 days' do
      link = create(:link, user: user)
      ApiRequest.create!(plan: plan, logable: link, created_at: 31.days.ago)
      ApiRequest.create!(plan: plan, logable: link)

      expect(plan.links_created_within_last_30_days).to eq(1)
    end

    it 'excludes non-Link api_requests' do
      link = create(:link, user: user)
      brand_page = create(:brand_page, user: user)
      ApiRequest.create!(plan: plan, logable: link)
      ApiRequest.create!(plan: plan, logable: brand_page)

      expect(plan.links_created_within_last_30_days).to eq(1)
    end
  end

  describe '#qr_codes_created_within_last_30_days' do
    it 'counts QrCode api_requests within the last 30 days' do
      link = create(:link, user: user)
      qr_code = build(:qr_code, link: link, user: user)
      qr_code.save(validate: false)
      ApiRequest.create!(plan: plan, logable: qr_code)

      expect(plan.qr_codes_created_within_last_30_days).to eq(1)
    end
  end

  describe '#brand_pages_created_within_last_30_days' do
    it 'counts BrandPage api_requests within the last 30 days' do
      brand_page = create(:brand_page, user: user)
      ApiRequest.create!(plan: plan, logable: brand_page)

      expect(plan.brand_pages_created_within_last_30_days).to eq(1)
    end
  end

  describe '#links_limit_exceeded?' do
    it 'returns false when under the limit' do
      expect(plan.links_limit_exceeded?).to be false
    end

    it 'returns true when limit is reached' do
      link = create(:link, user: user)
      plan.links.times { ApiRequest.create!(plan: plan, logable: link) }

      expect(plan.links_limit_exceeded?).to be true
    end
  end

  describe '#qr_codes_limit_exceeded?' do
    it 'returns false when under the limit' do
      expect(plan.qr_codes_limit_exceeded?).to be false
    end

    it 'returns true when limit is reached' do
      link = create(:link, user: user)
      qr_code = build(:qr_code, link: link, user: user)
      qr_code.save(validate: false)
      plan.qr_codes.times { ApiRequest.create!(plan: plan, logable: qr_code) }

      expect(plan.qr_codes_limit_exceeded?).to be true
    end
  end

  describe '#brand_pages_limit_exceeded?' do
    it 'returns false when under the limit' do
      expect(plan.brand_pages_limit_exceeded?).to be false
    end

    it 'returns true when limit is reached' do
      brand_page = create(:brand_page, user: user)
      plan.brand_pages.times { ApiRequest.create!(plan: plan, logable: brand_page) }

      expect(plan.brand_pages_limit_exceeded?).to be true
    end
  end

  describe '#campaigns' do
    it 'returns Free limit by default' do
      expect(plan.campaigns).to eq(1)
    end
  end

  describe '#campaigns_limit_exceeded?' do
    it 'returns true when campaign count reaches the plan cap' do
      expect(plan.campaigns_limit_exceeded?(user)).to be true
    end
  end
end
