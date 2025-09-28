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
class BrandPage < ApplicationRecord
  belongs_to :user
  belongs_to :draft_source, class_name: "BrandPage", optional: true
  has_one :draft_version, class_name: "BrandPage", foreign_key: :draft_source_id, dependent: :destroy
  # has_many :clicks, dependent: :destroy
  has_many :api_requests, as: :logable, dependent: :destroy
  validates_presence_of :content, :lookup_code
  validates_uniqueness_of :lookup_code

  before_validation :set_lookup_code, on: :create

  after_create :update_lookup_code

  validates :content, presence: true
  validates :lookup_code, presence: true, uniqueness: true

  scope :published, -> { where.not(published_at: nil) }
  scope :drafts, -> { where(published_at: nil) }

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

  def status
    published? ? "PUBLISHED" : "DRAFT"
  end

  def publish!
    update!(published_at: Time.current)
  end

  def unpublish!
    update!(published_at: nil)
  end

  def sqids_service
    @sqids_service ||= SqidsService.instance
  end
end
