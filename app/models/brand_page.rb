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
class BrandPage < ApplicationRecord
  belongs_to :user
  belongs_to :published_version, class_name: "BrandPage", optional: true
  has_one :draft_version, class_name: "BrandPage", foreign_key: :published_version_id, dependent: :nullify
  # has_many :clicks, dependent: :destroy
  has_many :api_requests, as: :logable, dependent: :destroy

  validates_presence_of :content, :lookup_code
  validates_uniqueness_of :lookup_code

  before_validation :set_lookup_code, on: :create

  after_create :update_lookup_code

  validates :content, presence: true
  validates :lookup_code, presence: true, uniqueness: true

  # Status constants
  STATUS_DRAFT = "DRAFT"
  STATUS_PUBLISHED = "PUBLISHED"

  validates :status, inclusion: { in: [ STATUS_DRAFT, STATUS_PUBLISHED ] }

  scope :published, -> { where(status: STATUS_PUBLISHED) }
  scope :drafts, -> { where(status: STATUS_DRAFT) }

  def published?
    status == STATUS_PUBLISHED
  end

  def draft?
    status == STATUS_DRAFT
  end

  def publish!
    raise StandardError, "You can only publish the draft version, you cannot publish a published version" if published?

    published_page = ActiveRecord::Base.transaction do
      if published_version.present?
        # Update existing published version with draft content
        published_version.update!(
          content: content,
          status: STATUS_PUBLISHED,
          # Reset published_at and published_url since the worker will update them
          published_at: nil,
          published_url: nil
        )
        published_version
      else
        # Create new published version from this draft
        new_published_version = self.dup
        new_published_version.published_version = nil  # Published version doesn't point to anything
        new_published_version.status = STATUS_PUBLISHED
        new_published_version.published_at = nil
        new_published_version.lookup_code = nil  # Will be regenerated
        new_published_version.save!

        # Update this draft to point to the new published version
        update!(published_version: new_published_version)
        new_published_version
      end
    end

    PublishJob.perform_async(published_page.lookup_code)
    published_page
  end

  def unpublish!
    raise StandardError, "You can only unpublish the published version, you cannot unpublish a draft version" if draft?

    ActiveRecord::Base.transaction do
      draft_version.update!(
        published_version: nil,
        published_url: nil,
        published_at: nil
      ) if draft_version
    end

    UnpublishJob.perform_async(lookup_code)
  end

  def get_published_version
    return self if published?
    # In async workflow, published_version might exist but not have published_at set yet
    published_version if published_version.present?
  end

  def get_draft_version
    return self if draft?
    draft_version || self
  end

  def set_lookup_code
    self.lookup_code = SecureRandom.uuid if lookup_code.blank?
  end

  def update_lookup_code
    self.update_column(:lookup_code, sqids_service.generate(id, user_id))
  end

  def decode(lookup_code)
    sqids_service.decode(lookup_code)
  end

  def find_by_lookup_code(lookup_code)
    user_id, brand_page_id = decode(lookup_code)
    Rails.logger.info("Decoded brand_page_id: #{brand_page_id}, user_id: #{user_id}")
    BrandPage.find_by(id: brand_page_id)
  end

  private

  def sqids_service
    @sqids_service ||= PagesSqidsService.instance
  end
end
