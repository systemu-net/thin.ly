# Evaluates routing rules against a click context, returning the first
# match for deterministic rules and using weighted random for percentage
# splits.  Called from LinkGovernance#resolve_destination.
#
# Usage:
#   rule = RoutingRulesEngine.evaluate(active_rules, { country: "US", device_type: "mobile" })
#   rule&.destination_url
class RoutingRulesEngine
  class << self
    def evaluate(rules, context)
      percentage_rules = []

      rules.each do |rule|
        case rule.rule_type
        when "percentage"
          percentage_rules << rule
        else
          return rule if matches?(rule, context)
        end
      end

      # Percentage-based A/B split: pick one rule weighted by its weight field.
      pick_weighted(percentage_rules) if percentage_rules.any?
    end

    private

    # ── Deterministic matchers ──────────────────────────────────────────

    def matches?(rule, context)
      case rule.rule_type
      when "geo"         then match_geo(rule.conditions, context)
      when "device"      then match_device(rule.conditions, context)
      when "referrer"    then match_referrer(rule.conditions, context)
      when "time_window" then match_time_window(rule.conditions, context)
      else false
      end
    end

    # conditions: { "countries" => ["US", "CA"] }
    def match_geo(conditions, context)
      countries = Array(conditions["countries"]).map(&:upcase)
      return false if countries.empty?

      countries.include?(context[:country].to_s.upcase)
    end

    # conditions: { "device_types" => ["mobile", "tablet"] }
    def match_device(conditions, context)
      types = Array(conditions["device_types"]).map(&:downcase)
      return false if types.empty?

      types.include?(context[:device_type].to_s.downcase)
    end

    # conditions: { "referrer_pattern" => "twitter\\.com|x\\.com" }
    def match_referrer(conditions, context)
      pattern = conditions["referrer_pattern"].to_s
      return false if pattern.blank?

      Regexp.new(pattern, Regexp::IGNORECASE).match?(context[:referrer].to_s)
    end

    # conditions: { "start_time" => "09:00", "end_time" => "17:00", "timezone" => "America/New_York" }
    def match_time_window(conditions, context)
      tz    = ActiveSupport::TimeZone[conditions["timezone"]] || Time.zone
      now   = (context[:timestamp] || Time.current).in_time_zone(tz)
      start = Tod::TimeOfDay.parse(conditions["start_time"]) rescue nil
      stop  = Tod::TimeOfDay.parse(conditions["end_time"])   rescue nil

      # Fallback to basic hour comparison when Tod is unavailable
      if start.nil? || stop.nil?
        return match_time_window_basic(conditions, now)
      end

      current = Tod::TimeOfDay.new(now.hour, now.min)
      Tod::Shift.new(start, stop).include?(current)
    rescue StandardError
      match_time_window_basic(conditions, context[:timestamp] || Time.current)
    end

    # Simple hour-based check used when Tod gem is not available.
    def match_time_window_basic(conditions, now)
      start_h, start_m = conditions["start_time"].to_s.split(":").map(&:to_i)
      end_h, end_m     = conditions["end_time"].to_s.split(":").map(&:to_i)
      return false unless start_h && end_h

      current_minutes = now.hour * 60 + now.min
      start_minutes   = start_h * 60 + (start_m || 0)
      end_minutes     = end_h * 60 + (end_m || 0)

      if start_minutes <= end_minutes
        current_minutes.between?(start_minutes, end_minutes)
      else
        # Overnight window (e.g., 22:00–06:00)
        current_minutes >= start_minutes || current_minutes <= end_minutes
      end
    end

    # ── Weighted random pick ────────────────────────────────────────────

    # Weights are percentages (1–100) of *total traffic*, not shares of each
    # other.  Roll against 100 so the unallocated remainder (e.g. 99% when
    # one rule has weight=1) returns nil and falls through to original_url.
    # When weights sum beyond 100 the ceiling is clamped to their total so
    # every rule still gets its proportional share and nil is never returned.
    def pick_weighted(rules)
      total   = rules.sum(&:weight)
      return nil if total.zero?

      ceiling = [ total, 100 ].max
      roll    = rand(1..ceiling)
      cursor  = 0
      rules.each do |rule|
        cursor += rule.weight
        return rule if roll <= cursor
      end
      nil # unallocated traffic → falls through to link.original_url
    end
  end
end
