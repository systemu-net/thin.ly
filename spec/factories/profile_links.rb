# == Schema Information
#
# Table name: profile_links
#
#  id             :bigint           not null, primary key
#  pinned         :boolean          default(FALSE), not null
#  position       :integer          default(0), not null
#  tag            :string
#  title_override :string
#  visible        :boolean          default(TRUE), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  link_id        :bigint           not null
#  profile_id     :bigint           not null
#
# Indexes
#
#  index_profile_links_on_link_id                  (link_id)
#  index_profile_links_on_profile_id               (profile_id)
#  index_profile_links_on_profile_id_and_link_id   (profile_id,link_id) UNIQUE
#  index_profile_links_on_profile_id_and_position  (profile_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (link_id => links.id)
#  fk_rails_...  (profile_id => profiles.id)
#
FactoryBot.define do
  factory :profile_link do
    profile
    link { association :link, user: profile.user }
    sequence(:position) { |n| n }
    pinned { false }
    visible { true }
  end
end
