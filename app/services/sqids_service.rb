require "singleton"

class SqidsService
  ALPHABET = "CV0vsUKbkZwThWHLqypPj46z1FG9lmMX7dSOaiYR85AoeQrcgBx2u3IJNtfDnE".freeze

  include Singleton

  def initialize
    @sqids = Sqids.new(alphabet: ALPHABET)
    @mutex = Mutex.new
  end

  def generate(link_id, user_id)
    @mutex.synchronize { @sqids.encode([ user_id, link_id ]) }
  end

  def decode(code)
    @mutex.synchronize { @sqids.decode(code) }
  end
end
