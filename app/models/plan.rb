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
class Plan < ApplicationRecord
  belongs_to :subscription
  has_many :api_requests, dependent: :destroy

  DEFAULT_PLAN = {
    links: 50,
    qr_codes: 50,
    brand_pages: 1,
    campaigns: 1,
    name: "Free"
  }

  def links_created_within_last_30_days
    api_requests.where(logable_type: "Link").where("created_at >= ?", 30.days.ago).count
  end

  def qr_codes_created_within_last_30_days
    api_requests.where(logable_type: "QrCode").where("created_at >= ?", 30.days.ago).count
  end

  def brand_pages_created_within_last_30_days
    api_requests.where(logable_type: "BrandPage").where("created_at >= ?", 30.days.ago).count
  end

  def links_limit_exceeded?
    links_created_within_last_30_days >= links
  end

  def qr_codes_limit_exceeded?
    qr_codes_created_within_last_30_days >= qr_codes
  end

  def brand_pages_limit_exceeded?
    brand_pages_created_within_last_30_days >= brand_pages
  end

  def campaigns_limit_exceeded?(user)
    user.link_campaigns.count >= campaigns
  end
end
