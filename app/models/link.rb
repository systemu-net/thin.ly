# == Schema Information
#
# Table name: links
#
#  id           :integer          not null, primary key
#  lookup_code  :string
#  original_url :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :integer          not null
#
# Indexes
#
#  index_links_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class Link < ApplicationRecord
  belongs_to :user
  has_many :qr_codes, -> { order(created_at: :desc) }
  has_many :clicks, dependent: :destroy
  has_many :api_requests, as: :logable, dependent: :destroy

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

  private

  def original_url_format
    uri = URI.parse(original_url)
    errors.add(:original_url, "Invalid URL format") if uri.host.nil?
  rescue URI::InvalidURIError => e
    Rails.logger.error(e.message)
  end

  def set_lookup_code
    self.lookup_code = SecureRandom.uuid
  end

  def update_lookup_code
    self.update_column(:lookup_code, sqids_service.generate(id, user_id))
  end

  def decode(lookup_code)
    sqids_service.decode(lookup_code)
  end

  def find_by_lookup_code(lookup_code)
    link_id, _user_id = decode(lookup_code)
    Link.find_by(id: link_id)
  end

  def sqids_service
    @sqids_service ||= SqidsService.instance
  end
end
