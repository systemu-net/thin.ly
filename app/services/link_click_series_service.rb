# Builds a per-link daily click sparkline ([Int] * `days`, oldest → newest) for
# a set of links in a single query. Used by the public profile view and the
# owner's Links editor so link rows show real recent traffic.
class LinkClickSeriesService
  def self.call(link_ids, days: 7, now: Time.current)
    new(link_ids, days: days, now: now).call
  end

  def initialize(link_ids, days:, now:)
    @link_ids = Array(link_ids).uniq
    @days = days
    @now = now
  end

  # => { link_id => [c0, c1, …, c(days-1)] }
  def call
    return {} if @link_ids.empty?

    anchor = @now.beginning_of_day
    buckets = Array.new(@days) { |i| (anchor - (@days - 1 - i).days).to_i }

    rows = Click
      .where(link_id: @link_ids, created_at: (anchor - (@days - 1).days)..@now)
      .group(:link_id, Arel.sql("date_trunc('day', created_at)"))
      .count

    counts = Hash.new { |h, k| h[k] = Hash.new(0) }
    rows.each { |(link_id, day), count| counts[link_id][to_epoch(day)] += count }

    @link_ids.index_with { |link_id| buckets.map { |epoch| counts[link_id][epoch] } }
  end

  private

  def to_epoch(day)
    time = day.is_a?(Time) || day.is_a?(ActiveSupport::TimeWithZone) ? day : Time.zone.parse(day.to_s)
    time.beginning_of_day.to_i
  end
end
