# == Schema Information
#
# Table name: plans
#
#  id              :bigint           not null, primary key
#  brand_pages     :integer
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
FactoryBot.define do
  factory :plan do
    subscription { nil }
    links { 1 }
    qr_codes { 1 }
    pages { 1 }
  end
end
