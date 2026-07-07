# == Schema Information
#
# Table name: subscriptions
#
#  id                   :bigint           not null, primary key
#  cancel_at_period_end :boolean          default(FALSE), not null
#  current_period_end   :datetime
#  current_period_start :datetime
#  interval             :string
#  product              :string           default("linkly"), not null
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
#  index_subscriptions_on_user_id              (user_id)
#  index_subscriptions_on_user_id_and_product  (user_id,product)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
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
