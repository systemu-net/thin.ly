# == Schema Information
#
# Table name: subscriptions
#
#  id                   :integer          not null, primary key
#  current_period_end   :datetime
#  current_period_start :datetime
#  interval             :string
#  status               :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  customer_id          :string
#  subscription_id      :string
#  user_id              :integer          not null
#
# Indexes
#
#  index_subscriptions_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class Subscription < ApplicationRecord
  belongs_to :user
  has_many :plans, dependent: :destroy

  after_commit :create_default_plan, on: :create

  private

  def create_default_plan
    return if plans.any?

    plans.create(Plan::DEFAULT_PLAN)
  end
end
