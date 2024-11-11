class Shortener
  attr_reader :url

  def initialize(url)
    @url = url
  end


  def self.lookup_code(url)
    new(url).lookup_code
  end

  def lookup_code
  end

  def self.find_url(lookup_code)
    new(nil).find_url(lookup_code)
  end

  def find_url(lookup_code)
    # implementation
  end
end
