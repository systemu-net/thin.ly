class Link < ApplicationRecord
  validates_presence_of :original_url, :lookup_code
  validates_uniqueness_of :lookup_code
  validate :original_url_format

  after_create :update_lookup_code
  before_validation :set_lookup_code, on: :create

  def shortened_url
    "http://localhost:3000/#{lookup_code}"
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
    link_id, user_id = decode(lookup_code)
    # Link.find_by(id: link_id, user_id: user_id)
    Link.find(link_id)
  end

  def sqids_service
    @sqids_service ||= SqidsService.instance
  end

  def user_id
    1
  end
end
