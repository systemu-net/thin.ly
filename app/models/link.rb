# == Schema Information
#
# Table name: links
#
#  id                   :bigint           not null, primary key
#  activates_at         :datetime
#  click_cap            :integer
#  clicks_count         :integer          default(0), not null
#  description          :text
#  expired_redirect_url :string
#  expires_at           :datetime
#  governance_enabled   :boolean          default(FALSE), not null
#  is_safe              :boolean
#  last_scanned_at      :datetime
#  lookup_code          :string
#  original_url         :string
#  password_digest      :string
#  password_protected   :boolean          default(FALSE), not null
#  paused_redirect_url  :string
#  scan_failures        :integer          default(0)
#  state                :string           default("active"), not null
#  title                :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  link_campaign_id     :bigint
#  user_id              :bigint           not null
#
# Indexes
#
#  index_links_on_activates_at                 (activates_at)
#  index_links_on_expires_at                   (expires_at)
#  index_links_on_is_safe                      (is_safe)
#  index_links_on_is_safe_and_last_scanned_at  (is_safe,last_scanned_at)
#  index_links_on_last_scanned_at              (last_scanned_at)
#  index_links_on_link_campaign_id             (link_campaign_id)
#  index_links_on_state                        (state)
#  index_links_on_user_and_clicks_count        (user_id,clicks_count)
#  index_links_on_user_and_created             (user_id,created_at)
#  index_links_on_user_id                      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (link_campaign_id => link_campaigns.id)
#  fk_rails_...  (user_id => users.id)
#
class Link < ApplicationRecord
  include LinkGovernance

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
  before_validation :assign_default_campaign, on: :create
  before_validation :set_lookup_code, on: :create

  def shortened_url
    "#{ENV['DEV_HOST']}/#{lookup_code}"
  end

  # Host of the destination URL, e.g. "youtube.com" — shown under link rows on
  # the public profile. nil for malformed URLs.
  def host
    URI.parse(original_url.to_s).host
  rescue URI::InvalidURIError
    nil
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

  def assign_default_campaign
    return if link_campaign.present? || user.blank?

    self.link_campaign = user.link_campaigns.find_by(default: true)
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
    link_id = decode(lookup_code).first
    Rails.logger.info("Decoded link_id: #{link_id}")
    Link.find_by(id: link_id)
  end

  def sqids_service
    @sqids_service ||= SqidsService.instance
  end
end
