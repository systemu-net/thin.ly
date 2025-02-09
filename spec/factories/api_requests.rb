# == Schema Information
#
# Table name: api_requests
#
#  id           :integer          not null, primary key
#  logable_type :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  logable_id   :integer          not null
#  plan_id      :integer          not null
#
# Indexes
#
#  index_api_requests_on_logable  (logable_type,logable_id)
#  index_api_requests_on_plan_id  (plan_id)
#
# Foreign Keys
#
#  plan_id  (plan_id => plans.id)
#
FactoryBot.define do
  factory :api_request do
    plan { nil }
    logable { nil }
  end
end
