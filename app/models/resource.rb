# == Schema Information
#
# Table name: resources
#
#  id            :bigint           not null, primary key
#  linkable_type :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  linkable_id   :bigint           not null
#  page_id       :bigint           not null
#
# Indexes
#
#  index_resources_on_linkable           (linkable_type,linkable_id)
#  index_resources_on_page_and_linkable  (page_id,linkable_type,linkable_id)
#  index_resources_on_page_id            (page_id)
#
# Foreign Keys
#
#  fk_rails_...  (page_id => brand_pages.id)
#
class Resource < ApplicationRecord
  belongs_to :page, class_name: "BrandPage"
  belongs_to :linkable, polymorphic: true

  validates :page, presence: true
  validates :linkable, presence: true
  validates :linkable_type, inclusion: { in: %w[Link QrCode Image], message: "%{value} is not a valid linkable type" }

  # Scope to get resources by linkable type
  scope :links, -> { where(linkable_type: "Link") }
  scope :qr_codes, -> { where(linkable_type: "QrCode") }
  scope :images, -> { where(linkable_type: "Image") }
end
