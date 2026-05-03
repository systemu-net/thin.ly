# == Schema Information
#
# Table name: links
#
#  id                   :bigint           not null, primary key
#  activates_at         :datetime
#  click_cap            :integer
#  clicks_count         :integer          default(0), not null
#  description          :text
#  expired_redirect_url :string
#  expires_at           :datetime
#  governance_enabled   :boolean          default(FALSE), not null
#  is_safe              :boolean
#  last_scanned_at      :datetime
#  lookup_code          :string
#  original_url         :string
#  password_digest      :string
#  password_protected   :boolean          default(FALSE), not null
#  paused_redirect_url  :string
#  scan_failures        :integer          default(0)
#  state                :string           default("active"), not null
#  title                :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  link_campaign_id     :bigint
#  user_id              :bigint           not null
#
# Indexes
#
#  index_links_on_activates_at                 (activates_at)
#  index_links_on_expires_at                   (expires_at)
#  index_links_on_is_safe                      (is_safe)
#  index_links_on_is_safe_and_last_scanned_at  (is_safe,last_scanned_at)
#  index_links_on_last_scanned_at              (last_scanned_at)
#  index_links_on_link_campaign_id             (link_campaign_id)
#  index_links_on_state                        (state)
#  index_links_on_user_and_clicks_count        (user_id,clicks_count)
#  index_links_on_user_and_created             (user_id,created_at)
#  index_links_on_user_id                      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (link_campaign_id => link_campaigns.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :link do
    original_url { 'https://www.thin.ly/example' }
    title { nil }
    description { nil }
  end
end
