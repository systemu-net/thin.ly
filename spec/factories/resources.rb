# == Schema Information
#
# Table name: resources
#
#  id            :bigint           not null, primary key
#  color         :string
#  linkable_type :string           not null
#  sort_order    :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  linkable_id   :bigint           not null
#  page_id       :bigint           not null
#
# Indexes
#
#  index_resources_on_linkable                (linkable_type,linkable_id)
#  index_resources_on_page_and_linkable       (page_id,linkable_type,linkable_id)
#  index_resources_on_page_id                 (page_id)
#  index_resources_on_page_id_and_sort_order  (page_id,sort_order)
#
# Foreign Keys
#
#  fk_rails_...  (page_id => brand_pages.id)
#
FactoryBot.define do
  factory :resource do
    association :page, factory: :brand_page
    association :linkable, factory: :link

    trait :with_link do
      association :linkable, factory: :link
    end

    trait :with_qr_code do
      association :linkable, factory: :qr_code
    end
  end
end
