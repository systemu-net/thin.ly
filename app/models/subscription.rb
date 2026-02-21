# == Schema Information
#
# Table name: subscriptions
#
#  id                   :bigint           not null, primary key
#  cancel_at_period_end :boolean          default(FALSE), not null
#  current_period_end   :datetime
#  current_period_start :datetime
#  interval             :string
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
#  index_subscriptions_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Subscription < ApplicationRecord
  belongs_to :user
  has_many :plans, dependent: :destroy

  after_commit :create_default_plan, on: :create

  def plan
    @plan ||= plans.first
  end

  private

  def create_default_plan
    return if plans.any?

    plans.create(Plan::DEFAULT_PLAN)
  end
end
