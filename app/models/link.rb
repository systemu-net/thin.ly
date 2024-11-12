class Link < ApplicationRecord
  validates_presence_of :original_url, :lookup_code
  validates_uniqueness_of :lookup_code

  after_create :update_lookup_code
  before_validation :set_lookup_code, on: :create

  private

  def set_lookup_code
    self.lookup_code = SecureRandom.uuid
  end

  def update_lookup_code
    self.update_column(:lookup_code, sqids_service.generate(id, user_id))
  end

  def sqids_service
    @sqids_service ||= SqidsService.instance
  end

  def user_id
    1
  end
end
