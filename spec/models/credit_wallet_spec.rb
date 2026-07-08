# == Schema Information
#
# Table name: credit_wallets
#
#  id             :bigint           not null, primary key
#  budget_micros  :bigint           default(0), not null
#  input_cap      :bigint           not null
#  input_used     :bigint           default(0), not null
#  output_cap     :bigint           not null
#  output_used    :bigint           default(0), not null
#  overage_policy :string           default("throttle"), not null
#  period_end     :datetime
#  period_start   :datetime
#  plan_key       :string           not null
#  product        :string           default("levelcode"), not null
#  spent_micros   :bigint           default(0), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  user_id        :bigint           not null
#
# Indexes
#
#  index_credit_wallets_on_user_id              (user_id)
#  index_credit_wallets_on_user_id_and_product  (user_id,product) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require 'rails_helper'

RSpec.describe CreditWallet, type: :model do
  let(:user) { create(:user) }

  describe 'associations' do
    it 'belongs to a user' do
      assoc = described_class.reflect_on_association(:user)
      expect(assoc.macro).to eq(:belongs_to)
    end
  end

  describe 'validations' do
    subject { CreditWallet.for(user) }

    it 'is valid when provisioned from a plan' do
      expect(subject).to be_valid
    end

    it 'rejects an unknown overage policy' do
      subject.overage_policy = 'nope'
      expect(subject).not_to be_valid
    end

    it 'requires a plan_key' do
      subject.plan_key = nil
      expect(subject).not_to be_valid
    end
  end

  describe '.for' do
    it 'provisions a wallet seeded from the default plan' do
      wallet = CreditWallet.for(user)
      plan = Levelcode::PLANS.first

      expect(wallet).to be_persisted
      expect(wallet.product).to eq(Levelcode::PRODUCT)
      expect(wallet.plan_key).to eq(plan[:key])
      expect(wallet.input_cap).to eq(plan[:input_cap])
      expect(wallet.output_cap).to eq(plan[:output_cap])
      expect(wallet.overage_policy).to eq('throttle')
    end

    it 'is idempotent per [user, product]' do
      first = CreditWallet.for(user)
      second = CreditWallet.for(user)

      expect(second.id).to eq(first.id)
      expect(user.credit_wallets.count).to eq(1)
    end

    it 'seeds caps from a specified plan_key' do
      wallet = CreditWallet.for(user, plan_key: 'orbits_ultra')
      plan = Levelcode.plan('orbits_ultra')

      expect(wallet.plan_key).to eq('orbits_ultra')
      expect(wallet.input_cap).to eq(plan[:input_cap])
      expect(wallet.output_cap).to eq(plan[:output_cap])
    end
  end

  describe 'cap helpers' do
    let(:wallet) { CreditWallet.for(user) }

    it 'reports remaining tokens per dimension' do
      wallet.update!(input_used: 1_000_000, output_used: 500_000)

      expect(wallet.input_remaining).to eq(wallet.input_cap - 1_000_000)
      expect(wallet.output_remaining).to eq(wallet.output_cap - 500_000)
    end

    it 'never reports negative remaining' do
      wallet.update!(input_used: wallet.input_cap + 999)
      expect(wallet.input_remaining).to eq(0)
    end

    it 'flags cap_reached when input hits the cap' do
      wallet.update!(input_used: wallet.input_cap)
      expect(wallet.input_cap_reached?).to be true
      expect(wallet.cap_reached?).to be true
    end

    it 'flags cap_reached when output hits the cap' do
      wallet.update!(output_used: wallet.output_cap)
      expect(wallet.output_cap_reached?).to be true
      expect(wallet.cap_reached?).to be true
    end

    it 'is not over cap exactly at the cap' do
      wallet.update!(input_used: wallet.input_cap)
      expect(wallet.overage?).to be false
    end

    it 'is over cap past the cap' do
      wallet.update!(output_used: wallet.output_cap + 1)
      expect(wallet.overage?).to be true
    end
  end

  describe 'overage policy predicates' do
    let(:wallet) { CreditWallet.for(user) }

    it 'defaults to throttle' do
      expect(wallet.throttle?).to be true
      expect(wallet.topup?).to be false
      expect(wallet.stop?).to be false
    end

    it 'reflects a topup policy' do
      wallet.update!(overage_policy: 'topup')
      expect(wallet.topup?).to be true
    end

    it 'reflects a stop policy' do
      wallet.update!(overage_policy: 'stop')
      expect(wallet.stop?).to be true
    end
  end
end
