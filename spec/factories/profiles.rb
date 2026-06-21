# == Schema Information
#
# Table name: profiles
#
#  id              :bigint           not null, primary key
#  accent          :string           default("violet"), not null
#  bio             :text
#  display_name    :string
#  followers_count :integer          default(0), not null
#  following_count :integer          default(0), not null
#  handle          :string           not null
#  location        :string
#  privacy         :jsonb            not null
#  published_at    :datetime
#  social_order    :jsonb            not null
#  socials         :jsonb            not null
#  verified        :boolean          default(FALSE), not null
#  website         :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_profiles_on_lower_handle  (lower((handle)::text)) UNIQUE
#  index_profiles_on_user_id       (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :profile do
    sequence(:handle) { |n| "handle#{n}" }
    display_name { "Test User" }

    # User#create_default_profile (after_commit) already builds a profile, and
    # profiles.user_id is unique — so reuse that record instead of creating a
    # second one for the same user.
    initialize_with { create(:user).profile }
  end
end
