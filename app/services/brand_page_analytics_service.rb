# Aggregates real traffic for a user's pages, as shown on the /pages dashboard.
#
# The dashboard lists each page's DRAFT record, but the publicly-served page —
# and therefore every PageView — belongs to that draft's *published version*
# (see BrandPage#publish! and the tracking snippet in
# app/views/link_in_bio/static.html.erb, which posts the served page's
# lookup_code). So a draft's traffic is the page_views of its published_version;
# a draft that was never published reports zeros.
#
# Returns an array (one entry per draft), each:
#   { lookup_code:, views:, views_window:, trend_pct:, spark: [Int x WINDOW_DAYS] }
# keyed by the DRAFT lookup_code so the frontend can match `page.lookup_code`.
#   • views        — all-time page views
#   • views_window — views in the last WINDOW_DAYS
#   • trend_pct    — % change of views_window vs the preceding WINDOW_DAYS
#   • spark        — daily view counts for the last WINDOW_DAYS (oldest → newest)
class BrandPageAnalyticsService
  WINDOW_DAYS = 14

  def initialize(user, now: Time.current)
    @user = user
    @now = now
  end

  def call
    drafts = @user.brand_pages.drafts.includes(:published_version).to_a

    # draft lookup_code → published version id (the analytics source), or nil
    source_by_lookup = drafts.each_with_object({}) do |draft, acc|
      pv = draft.published_version
      acc[draft.lookup_code] = pv&.published? ? pv.id : nil
    end
    source_ids = source_by_lookup.values.compact.uniq

    return drafts.map { |d| zero_entry(d.lookup_code) } if source_ids.empty?

    totals = PageView.where(brand_page_id: source_ids).group(:brand_page_id).count

    # 2 * WINDOW_DAYS daily buckets, oldest → newest: [previous window][current window]
    buckets = day_buckets(2 * WINDOW_DAYS)
    daily = daily_counts(source_ids, buckets.first)
    bucket_epochs = buckets.map(&:to_i)

    drafts.map do |draft|
      source_id = source_by_lookup[draft.lookup_code]
      next zero_entry(draft.lookup_code) unless source_id

      per_day = bucket_epochs.map { |epoch| daily.dig(source_id, epoch) || 0 }
      previous = per_day.first(WINDOW_DAYS).sum
      current  = per_day.last(WINDOW_DAYS)

      {
        lookup_code: draft.lookup_code,
        views: totals[source_id].to_i,
        views_window: current.sum,
        trend_pct: percentage_change(current.sum, previous),
        spark: current
      }
    end
  end

  private

  def zero_entry(lookup_code)
    { lookup_code: lookup_code, views: 0, views_window: 0, trend_pct: 0, spark: Array.new(WINDOW_DAYS, 0) }
  end

  # `count` day-start Times ending at today, oldest → newest.
  def day_buckets(count)
    anchor = @now.beginning_of_day
    Array.new(count) { |i| anchor - (count - 1 - i).days }
  end

  # { brand_page_id => { day_epoch => count } } for views since `from`.
  def daily_counts(source_ids, from)
    rows = PageView
      .where(brand_page_id: source_ids, visited_at: from..@now)
      .group(:brand_page_id, Arel.sql("date_trunc('day', visited_at)"))
      .count

    rows.each_with_object(Hash.new { |h, k| h[k] = Hash.new(0) }) do |((bp_id, day), count), acc|
      acc[bp_id][to_epoch(day)] += count
    end
  end

  def to_epoch(day)
    time = day.is_a?(Time) || day.is_a?(ActiveSupport::TimeWithZone) ? day : Time.zone.parse(day.to_s)
    time.beginning_of_day.to_i
  end

  def percentage_change(current, previous)
    return 0 if previous.zero?
    (((current - previous) / previous.to_f) * 100).round
  end
end
