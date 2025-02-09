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
require 'rails_helper'

RSpec.describe Plan, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
