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
class CreditWallet < ApplicationRecord
  belongs_to :user

  # Past-cap behaviour (SPEC §5).
  OVERAGE_POLICIES = %w[throttle topup stop].freeze

  validates :product, :plan_key, presence: true
  validates :input_cap, :output_cap, presence: true
  validates :overage_policy, inclusion: { in: OVERAGE_POLICIES }

  # Find-or-provision the wallet for a user + product, seeding caps/policy from
  # the plan definition in Levelcode::PLANS. Idempotent per [user, product].
  def self.for(user, product: Levelcode::PRODUCT, plan_key: Levelcode::PLANS.first[:key])
    wallet = find_or_initialize_by(user: user, product: product)
    return wallet if wallet.persisted?

    plan = Levelcode.plan(plan_key) || Levelcode::PLANS.first
    wallet.plan_key = plan[:key]
    wallet.input_cap = plan[:input_cap]
    wallet.output_cap = plan[:output_cap]
    wallet.save!
    wallet
  end

  # True once either dimension has reached its cap for the current period.
  def cap_reached?
    input_cap_reached? || output_cap_reached?
  end

  def input_cap_reached?
    input_used >= input_cap
  end

  def output_cap_reached?
    output_used >= output_cap
  end

  # Tokens still available before the cap on each dimension (never negative).
  def input_remaining
    [ input_cap - input_used, 0 ].max
  end

  def output_remaining
    [ output_cap - output_used, 0 ].max
  end

  # Whether the wallet is currently over cap on either dimension — i.e. this
  # request would be served past the subsidized ceiling.
  def overage?
    input_used > input_cap || output_used > output_cap
  end

  def throttle?
    overage_policy == "throttle"
  end

  def topup?
    overage_policy == "topup"
  end

  def stop?
    overage_policy == "stop"
  end
end
