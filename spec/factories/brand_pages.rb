# == Schema Information
#
# Table name: brand_pages
#
#  id                   :bigint           not null, primary key
#  content              :jsonb            not null
#  description          :text
#  lookup_code          :string           not null
#  published_at         :datetime
#  published_url        :string
#  status               :string           default("DRAFT"), not null
#  title                :string           default("Untitled"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  published_version_id :bigint
#  user_id              :bigint           not null
#
# Indexes
#
#  index_brand_pages_on_lookup_code           (lookup_code) UNIQUE
#  index_brand_pages_on_published_at          (published_at)
#  index_brand_pages_on_published_version_id  (published_version_id)
#  index_brand_pages_on_status                (status)
#  index_brand_pages_on_user_id               (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (published_version_id => brand_pages.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :brand_page do
    association :user
    content { { title: "Test Page", links: [] } }
    sequence(:lookup_code) { |n| "test_code_#{n}" }
    status { "DRAFT" }

    trait :draft do
      published_at { nil }
      status { "DRAFT" }
    end

    trait :published do
      published_at { Time.current }
      status { "PUBLISHED" }
    end

    trait :with_published_version do
      after(:create) do |draft|
        published = create(:brand_page, :published, user: draft.user, content: draft.content)
        draft.update!(published_version: published)
      end
    end
  end
end
