# == Schema Information
#
# Table name: api_requests
#
#  id           :bigint           not null, primary key
#  logable_type :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  logable_id   :bigint           not null
#  plan_id      :bigint           not null
#
# Indexes
#
#  index_api_requests_on_logable  (logable_type,logable_id)
#  index_api_requests_on_plan_id  (plan_id)
#
# Foreign Keys
#
#  fk_rails_...  (plan_id => plans.id)
#
require 'rails_helper'

RSpec.describe ApiRequest, type: :model do
  let(:user) { create(:user) }
  let(:link) { create(:link, user: user) }

  describe 'associations' do
    it 'belongs to a plan' do
      assoc = described_class.reflect_on_association(:plan)
      expect(assoc.macro).to eq(:belongs_to)
    end

    it 'belongs to logable (polymorphic)' do
      assoc = described_class.reflect_on_association(:logable)
      expect(assoc.macro).to eq(:belongs_to)
      expect(assoc.options[:polymorphic]).to be true
    end
  end

  describe 'creation' do
    it 'can be created with a Link as logable' do
      plan = user.plan
      api_request = ApiRequest.create!(plan: plan, logable: link)

      expect(api_request).to be_persisted
      expect(api_request.logable_type).to eq('Link')
      expect(api_request.logable_id).to eq(link.id)
      expect(api_request.plan).to eq(plan)
    end

    it 'can be created with a BrandPage as logable' do
      plan = user.plan
      brand_page = create(:brand_page, user: user)
      api_request = ApiRequest.create!(plan: plan, logable: brand_page)

      expect(api_request.logable_type).to eq('BrandPage')
      expect(api_request.logable_id).to eq(brand_page.id)
    end

    it 'can be created with a QrCode as logable' do
      plan = user.plan
      qr_code = build(:qr_code, link: link, user: user)
      qr_code.save(validate: false)
      api_request = ApiRequest.create!(plan: plan, logable: qr_code)

      expect(api_request.logable_type).to eq('QrCode')
      expect(api_request.logable_id).to eq(qr_code.id)
    end
  end
end
