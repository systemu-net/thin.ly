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
FactoryBot.define do
  factory :subscription do
    plan_id { "MyString" }
    customer_id { "MyString" }
    user { nil }
    status { "MyString" }
    current_period_end { "2025-01-12 18:24:35" }
    current_period_start { "2025-01-12 18:24:35" }
    interval { "MyString" }
    subscription_id { "MyString" }
  end
end
