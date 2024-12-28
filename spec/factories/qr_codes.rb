# == Schema Information
#
# Table name: qr_codes
#
#  id         :integer          not null, primary key
#  image      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  link_id    :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_qr_codes_on_link_id  (link_id)
#  index_qr_codes_on_user_id  (user_id)
#
# Foreign Keys
#
#  link_id  (link_id => links.id)
#  user_id  (user_id => users.id)
#
FactoryBot.define do
  factory :qr_code do
    link { nil }
    user { nil }
  end
end
