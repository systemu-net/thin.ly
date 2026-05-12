module Api
  module V1
    class AnalyticsController < ApplicationController
      before_action :authenticate_user!

      ALLOWED_PERIODS = %w[24h 7d 30d all].freeze

      # GET /api/v1/analytics/clicks_timeline?period=24h|7d|30d|all
      #
      # Returns a fully-filled bucket series anchored at NOW and walking
      # backwards, so the most recent (possibly partial) bucket is always the
      # rightmost point on the chart. Granularity per period:
      #
      #   24h → 24 hourly buckets (this hour is the rightmost)
      #   7d  →  7 daily buckets (today is the rightmost)
      #   30d → 30 daily buckets (today is the rightmost)
      #   all → 12 monthly buckets (this month is the rightmost)
      def clicks_timeline
        period = ALLOWED_PERIODS.include?(params[:period]) ? params[:period] : "7d"
        now = Time.current
        config = period_config(period, now)

        buckets = build_buckets(config[:anchor], config[:granularity], config[:count])
        range_start = buckets.first[:starts_at]

        scoped = Click.joins(:link)
                      .where(links: { user_id: current_user.id })
                      .where(clicks: { created_at: range_start..now })

        counts = bucket_counts_by_epoch(scoped, config[:granularity])

        points = buckets.map do |b|
          {
            at: b[:label],
            starts_at: b[:starts_at].iso8601,
            clicks: counts[b[:starts_at].to_i].to_i
          }
        end

        total = points.sum { |p| p[:clicks] }
        window_seconds = (now - range_start).to_f
        days_in_range = [ (window_seconds / 1.day).round, 1 ].max
        avg_per_day = (total.to_f / days_in_range).round(1)

        render json: {
          period: period,
          granularity: config[:granularity].to_s,
          total_clicks: total,
          avg_per_day: avg_per_day,
          points: points
        }
      end

      private

      # The most recent bucket anchor is always `now` rolled back to the start
      # of its current bucket (e.g. start of the current hour / day / month).
      # We then walk `count - 1` units backwards to reach the oldest bucket.
      def period_config(period, now)
        case period
        when "24h" then { granularity: :hour, count: 24, anchor: now.beginning_of_hour }
        when "30d" then { granularity: :day, count: 30, anchor: now.beginning_of_day }
        when "all" then { granularity: :month, count: 12, anchor: now.beginning_of_month }
        else { granularity: :day, count: 7, anchor: now.beginning_of_day }
        end
      end

      # Returns `count` buckets ordered oldest → newest, ending at `anchor`.
      def build_buckets(anchor, granularity, count)
        Array.new(count) do |i|
          offset = count - 1 - i # i=0 → oldest, i=count-1 → newest (anchor)
          starts_at = case granularity
                      when :hour then anchor - offset.hours
                      when :day then anchor - offset.days
                      when :month then anchor.advance(months: -offset)
                      end
          {
            label: bucket_label(starts_at, granularity),
            starts_at: starts_at,
            granularity: granularity
          }
        end
      end

      def bucket_label(time, granularity)
        case granularity
        when :hour then time.strftime("%H:00")
        when :day then time.strftime("%a")
        when :month then time.strftime("%b")
        end
      end

      # Returns { unix_epoch_seconds => count }. Keying on integer epoch sidesteps
      # all Time/TimeWithZone equality and DST-edge-case quirks when matching
      # PG date_trunc output back to our Ruby-side bucket anchors.
      def bucket_counts_by_epoch(scope, granularity)
        sql_expr = case granularity
                   when :hour then "date_trunc('hour', clicks.created_at)"
                   when :day then "date_trunc('day', clicks.created_at)"
                   when :month then "date_trunc('month', clicks.created_at)"
                   end
        scope.group(Arel.sql(sql_expr)).count.transform_keys do |k|
          t = k.is_a?(Time) || k.is_a?(ActiveSupport::TimeWithZone) ? k : Time.zone.parse(k.to_s)
          t.to_i
        end
      end
    end
  end
end
