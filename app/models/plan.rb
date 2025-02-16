# == Schema Information
#
# Table name: plans
#
#  id              :integer          not null, primary key
#  links           :integer
#  name            :string           default("Free"), not null
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
  has_many :api_requests, dependent: :destroy

  DEFAULT_PLAN = {
    links: 50,
    qr_codes: 5,
    pages: 1,
    name: "Free"
  }

  def links_created_within_last_30_days
    api_requests.where(logable_type: "Link").where("created_at >= ?", 30.days.ago).count
  end

  def qr_codes_created_within_last_30_days
    api_requests.where(logable_type: "QrCode").where("created_at >= ?", 30.days.ago).count
  end

  def pages_created_within_last_30_days
    api_requests.where(logable_type: "Page").where("created_at >= ?", 30.days.ago).count
  end

  def links_limit_exceeded?
    links_created_within_last_30_days >= links
  end

  def qr_codes_limit_exceeded?
    qr_codes_created_within_last_30_days >= qr_codes
  end

  def pages_limit_exceeded?
    pages_created_within_last_30_days >= pages
  end
end
