class Shortener
  attr_reader :url, :link_model

  def initialize(url, link_model = Link)
    @url = url
    @link_model = link_model
  end

  def self.lookup_code(url)
    new(url).lookup_code
  end

  def generate_short_link
    link_model.create(original_url: url, lookup_code: lookup_code)
  end

  def lookup_code
    SecureRandom.uuid.slice(0, 7)
    # sqids_service.generate(2, 1)
  end

  private

  def sqids_service
    @sqids_service ||= SqidsService.instance
  end
end
