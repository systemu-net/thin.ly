# == Schema Information
#
# Table name: links
#
#  id              :bigint           not null, primary key
#  clicks_count    :integer          default(0), not null
#  description     :text
#  is_safe         :boolean
#  last_scanned_at :datetime
#  lookup_code     :string
#  original_url    :string
#  scan_failures   :integer          default(0)
#  title           :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_links_on_is_safe                      (is_safe)
#  index_links_on_is_safe_and_last_scanned_at  (is_safe,last_scanned_at)
#  index_links_on_last_scanned_at              (last_scanned_at)
#  index_links_on_user_and_clicks_count        (user_id,clicks_count)
#  index_links_on_user_and_created             (user_id,created_at)
#  index_links_on_user_id                      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Link < ApplicationRecord
  belongs_to :user
  has_many :qr_codes, -> { order(created_at: :desc) }, dependent: :destroy
  has_many :clicks, dependent: :destroy
  has_many :api_requests, as: :logable, dependent: :destroy
  has_many :resources, as: :linkable, dependent: :destroy
  has_many :brand_pages, through: :resources, source: :page
  has_many :threat_detections, as: :detectable, dependent: :destroy

  validates_presence_of :original_url, :lookup_code
  validates_uniqueness_of :lookup_code
  validate :original_url_format

  after_create :update_lookup_code
  before_validation :set_lookup_code, on: :create

  def shortened_url
    "#{ENV['DEV_HOST']}/#{lookup_code}"
  end

  def has_qr_code?(user)
    qr_codes.where(user_id: user.id).any?
  end

  scope :safe_links, -> { where(is_safe: true) }
  scope :unsafe_links, -> { where(is_safe: false) }
  scope :unscanned_links, -> { where(is_safe: nil) }

  # Sorting scopes
  scope :by_created_asc, -> { order(created_at: :asc) }
  scope :by_created_desc, -> { order(created_at: :desc) }
  scope :by_clicks_asc, -> { order(clicks_count: :asc) }
  scope :by_clicks_desc, -> { order(clicks_count: :desc) }
  scope :by_last_clicked_asc, -> {
    left_joins(:clicks)
      .group(:id)
      .order(Arel.sql("MAX(clicks.created_at) ASC NULLS FIRST"))
  }
  scope :by_last_clicked_desc, -> {
    left_joins(:clicks)
      .group(:id)
      .order(Arel.sql("MAX(clicks.created_at) DESC NULLS LAST"))
  }

  private

  def original_url_format
    uri = URI.parse(original_url)
    errors.add(:original_url, "Invalid URL format") if uri.host.nil?
  rescue URI::InvalidURIError => e
    Rails.logger.error(e.message)
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
    user_id, link_id = decode(lookup_code)
    Rails.logger.info("Decoded link_id: #{link_id}, user_id: #{user_id}")
    Link.find_by(id: link_id)
  end

  def sqids_service
    @sqids_service ||= SqidsService.instance
  end
end
