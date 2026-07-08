# == Schema Information
#
# Table name: subscriptions
#
#  id                   :bigint           not null, primary key
#  cancel_at_period_end :boolean          default(FALSE), not null
#  current_period_end   :datetime
#  current_period_start :datetime
#  interval             :string
#  product              :string           default("linkly"), not null
#  status               :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  customer_id          :string
#  stripe_price_id      :string
#  subscription_id      :string
#  user_id              :bigint           not null
#
# Indexes
#
#  index_subscriptions_on_user_id              (user_id)
#  index_subscriptions_on_user_id_and_product  (user_id,product)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require 'rails_helper'

RSpec.describe Subscription, type: :model do
  let(:user) { create(:user) }

  describe 'associations' do
    it 'belongs to a user' do
      assoc = described_class.reflect_on_association(:user)
      expect(assoc.macro).to eq(:belongs_to)
    end

    it 'has many plans with dependent destroy' do
      assoc = described_class.reflect_on_association(:plans)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end
  end

  describe 'default plan creation' do
    it 'automatically creates a default plan after creation' do
      subscription = user.subscriptions.first
      expect(subscription.plans.count).to eq(1)
      expect(subscription.plan.name).to eq('Free')
    end

    it 'does not create duplicate plans if one already exists' do
      subscription = user.subscriptions.first
      expect(subscription.plans.count).to eq(1)

      # Trigger callback again manually
      subscription.send(:create_default_plan)
      expect(subscription.plans.count).to eq(1)
    end
  end

  describe '#plan' do
    it 'returns the first plan' do
      subscription = user.subscriptions.first
      expect(subscription.plan).to eq(subscription.plans.first)
    end

    it 'memoizes the result' do
      subscription = user.subscriptions.first
      first_call = subscription.plan
      second_call = subscription.plan
      expect(first_call).to equal(second_call)
    end
  end

  describe 'columns' do
    it 'has cancel_at_period_end defaulting to false' do
      subscription = user.subscriptions.first
      expect(subscription.cancel_at_period_end).to be false
    end

    it 'supports subscription metadata fields' do
      subscription = user.subscriptions.first
      subscription.update!(
        status: 'active',
        interval: 'month',
        subscription_id: 'sub_test123',
        stripe_price_id: 'price_test123',
        customer_id: 'cus_test123',
        current_period_start: Time.current,
        current_period_end: 30.days.from_now,
        cancel_at_period_end: true
      )

      subscription.reload
      expect(subscription.status).to eq('active')
      expect(subscription.interval).to eq('month')
      expect(subscription.subscription_id).to eq('sub_test123')
      expect(subscription.stripe_price_id).to eq('price_test123')
      expect(subscription.customer_id).to eq('cus_test123')
      expect(subscription.cancel_at_period_end).to be true
      expect(subscription.current_period_start).to be_present
      expect(subscription.current_period_end).to be_present
    end
  end
end
