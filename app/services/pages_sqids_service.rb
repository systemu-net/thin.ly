require "singleton"

class PagesSqidsService
  ALPHABET = "34h9adtg0ixlusj67eqpb8zn5or2mfyc1vwk".freeze
  MIN_LENGTH = 6

  include Singleton

  def initialize
    @sqids = Sqids.new(alphabet: ALPHABET, min_length: MIN_LENGTH)
    @mutex = Mutex.new
  end

  def generate(link_id, user_id)
    @mutex.synchronize { @sqids.encode([ user_id, link_id ]) }
  end

  def decode(lookup_code)
    @mutex.synchronize { @sqids.decode(lookup_code) }
  end
end
