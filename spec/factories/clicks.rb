# == Schema Information
#
# Table name: clicks
#
#  id         :integer          not null, primary key
#  country    :string
#  ip_address :string
#  referrer   :string
#  user_agent :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  link_id    :integer          not null
#
# Indexes
#
#  index_clicks_on_link_id  (link_id)
#
# Foreign Keys
#
#  link_id  (link_id => links.id)
#
FactoryBot.define do
  factory :click do
    link { nil }
  end
end
