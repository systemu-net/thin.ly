# == Schema Information
#
# Table name: api_requests
#
#  id           :bigint           not null, primary key
#  logable_type :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  logable_id   :bigint           not null
#  plan_id      :bigint           not null
#
# Indexes
#
#  index_api_requests_on_logable  (logable_type,logable_id)
#  index_api_requests_on_plan_id  (plan_id)
#
# Foreign Keys
#
#  fk_rails_...  (plan_id => plans.id)
#
require 'rails_helper'

RSpec.describe ApiRequest, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
