# frozen_string_literal: true

# Minimal in-memory Redis stand-in for hermetic specs. The app skips the real
# `$redis` in test (config/initializers/redis.rb: `unless Rails.env.test?`), so
# any code path that touches Redis — Levelcode::OneTimeCode (single-use codes),
# Levelcode::EditorToken (jti denylist), Levelcode::Metering (hot counters) — needs a
# fake. This implements only the commands those services use.
#
# Usage (scoped, save/restore so it never leaks into unrelated specs):
#   around { |ex| with_fake_redis { ex.run } }
class FakeRedis
  def initialize
    @strings = {}   # key => value
    @sets    = {}   # key => Set
    @expires = {}   # key => monotonic-ish marker (unused for logic; TTLs are no-ops)
  end

  # -- strings ----------------------------------------------------------------
  def set(key, val)
    @strings[key.to_s] = val.to_s
    "OK"
  end

  def setex(key, _ttl, val)
    set(key, val)
  end

  def get(key)
    @strings[key.to_s]
  end

  # Atomic get-and-delete — the property OneTimeCode relies on for single-use.
  def getdel(key)
    @strings.delete(key.to_s)
  end

  def del(*keys)
    keys.flatten.count { |k| @strings.delete(k.to_s) || @sets.delete(k.to_s) }
  end

  def mget(*keys)
    keys.flatten.map { |k| @strings[k.to_s] }
  end

  def incrby(key, by)
    @strings[key.to_s] = (@strings[key.to_s].to_i + by.to_i).to_s
    @strings[key.to_s].to_i
  end

  # -- sets -------------------------------------------------------------------
  def sadd(key, member)
    (@sets[key.to_s] ||= Set.new).add(member.to_s)
    1
  end

  def sismember(key, member)
    (@sets[key.to_s] || Set.new).include?(member.to_s)
  end

  # -- ttl (no-op; specs don't assert expiry timing) --------------------------
  def expire(key, _ttl)
    @expires[key.to_s] = true
  end

  # -- pipeline ---------------------------------------------------------------
  # Metering.record wraps writes in `$redis.pipelined { |p| ... }`. The fake just
  # yields itself so the buffered commands run inline.
  def pipelined
    yield self
    []
  end
end

module FakeRedisHelper
  def with_fake_redis
    prev = defined?($redis) ? $redis : nil
    $redis = FakeRedis.new
    yield
  ensure
    $redis = prev
  end
end

RSpec.configure do |config|
  config.include FakeRedisHelper
end
