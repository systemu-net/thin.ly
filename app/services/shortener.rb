class Shortener
  attr_reader :url, :user_id, :link_model, :attributes

  def initialize(url, user_id, attributes = {}, link_model = Link)
    @url = url
    @user_id = user_id
    @attributes = attributes || {}
    @link_model = link_model
  end

  def generate_short_link
    link_model.create({ original_url: url, user_id: user_id }.merge(attributes))
  end

  def lookup_code
    link_model.find_by(original_url: url).lookup_code
  end
end
