# == Schema Information
#
# Table name: plans
#
#  id              :integer          not null, primary key
#  links           :integer
#  pages           :integer
#  qr_codes        :integer
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  subscription_id :integer          not null
#
# Indexes
#
#  index_plans_on_subscription_id  (subscription_id)
#
# Foreign Keys
#
#  subscription_id  (subscription_id => subscriptions.id)
#
class Plan < ApplicationRecord
  belongs_to :subscription

  DEFAULT_PLAN = {
    links: 50,
    qr_codes: 5,
    pages: 1
  }
end
