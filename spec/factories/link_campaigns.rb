# == Schema Information
#
# Table name: link_campaigns
#
#  id           :bigint           not null, primary key
#  accent_color :string           default("#7c3aed"), not null
#  description  :text
#  name         :string           not null
#  state        :string           default("active"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_link_campaigns_on_accent_color  (accent_color)
#  index_link_campaigns_on_user_id       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :link_campaign do
    name { "Test Campaign" }
    state { "active" }
    description { "A test campaign" }
    association :user
  end
end
