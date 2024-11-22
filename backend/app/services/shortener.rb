class Shortener
  attr_reader :url, :link_model

  def initialize(url, link_model = Link)
    @url = url
    @link_model = link_model
  end

  def generate_short_link
    link_model.create(original_url: url)
  end

  def lookup_code
    link_model.find_by(original_url: url).lookup_code
  end
end
