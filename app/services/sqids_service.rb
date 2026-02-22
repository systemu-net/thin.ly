require "singleton"

class SqidsService
  ALPHABET = "CV0vsUKbkZwThWHLqypPj46z1FG9lmMX7dSOaiYR85AoeQrcgBx2u3IJNtfDnE".freeze
  MIN_LENGTH = 7

  include Singleton

  def initialize
    @sqids = Sqids.new(alphabet: ALPHABET, min_length: MIN_LENGTH)
    @mutex = Mutex.new
  end

  def generate(link_id, user_id = nil)
    @mutex.synchronize { @sqids.encode([ link_id ]) }
  end

  def decode(lookup_code)
    @mutex.synchronize { @sqids.decode(lookup_code) }
  end
end
