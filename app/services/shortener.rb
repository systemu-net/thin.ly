class Shortener
  attr_reader :url, :user_id, :link_model

  def initialize(url, user_id, link_model = Link)
    @url = url
    @user_id = user_id
    @link_model = link_model
  end

  def generate_short_link
    link_model.create(original_url: url, user_id: user_id)
  end

  def lookup_code
    link_model.find_by(original_url: url).lookup_code
  end
end
