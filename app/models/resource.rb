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
class Resource < ApplicationRecord
  belongs_to :page, class_name: "BrandPage"
  belongs_to :linkable, polymorphic: true

  validates :page, presence: true
  validates :linkable, presence: true
  validates :linkable_type, inclusion: { in: %w[Link QrCode Image], message: "%{value} is not a valid linkable type" }
  validates :sort_order, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Default scope to order by sort_order
  default_scope { order(sort_order: :asc) }

  # Scope to get resources by linkable type
  scope :links, -> { where(linkable_type: "Link") }
  scope :qr_codes, -> { where(linkable_type: "QrCode") }
  scope :images, -> { where(linkable_type: "Image") }

  # Auto-assign sort_order if not provided
  before_validation :set_sort_order, on: :create

  private

  def set_sort_order
    return if sort_order.present?

    max_sort_order = page.resources.unscoped.maximum(:sort_order) || -1
    self.sort_order = max_sort_order + 1
  end
end
