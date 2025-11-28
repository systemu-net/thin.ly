# == Schema Information
#
# Table name: links
#
#  id              :bigint           not null, primary key
#  description     :text
#  is_safe         :boolean
#  last_scanned_at :datetime
#  lookup_code     :string
#  original_url    :string
#  scan_failures   :integer          default(0)
#  title           :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_links_on_is_safe                      (is_safe)
#  index_links_on_is_safe_and_last_scanned_at  (is_safe,last_scanned_at)
#  index_links_on_last_scanned_at              (last_scanned_at)
#  index_links_on_user_id                      (user_id)
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
