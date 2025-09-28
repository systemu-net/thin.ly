# == Schema Information
#
# Table name: brand_pages
#
#  id              :bigint           not null, primary key
#  content         :jsonb            not null
#  lookup_code     :string           not null
#  published_at    :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  draft_source_id :bigint
#  user_id         :bigint           not null
#
# Indexes
#
#  index_brand_pages_on_draft_source_id  (draft_source_id)
#  index_brand_pages_on_lookup_code      (lookup_code) UNIQUE
#  index_brand_pages_on_published_at     (published_at)
#  index_brand_pages_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (draft_source_id => brand_pages.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :brand_page do
    user { nil }
    content { "" }
    published_at { "2025-06-19 15:37:09" }
    draft_source { nil }
  end
end
