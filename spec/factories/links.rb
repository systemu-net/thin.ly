# == Schema Information
#
# Table name: links
#
#  id           :bigint           not null, primary key
#  description  :text
#  lookup_code  :string
#  original_url :string
#  title        :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_links_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :link do
    original_url { 'https://www.thin.ly/example' }
    title { nil }
    description { nil }
  end
end
