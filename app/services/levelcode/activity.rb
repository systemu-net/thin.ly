# frozen_string_literal: true

module Levelcode
  # GitHub-style contribution activity for the account dashboard: per-day usage of the
  # editor (request counts + tokens + cost) with a per-model breakdown, aggregated from
  # the durable usage_events ledger. Days are bucketed by DATE(created_at) in the app
  # timezone-naive DB time (UTC) — a single grouped query, folded in Ruby.
  module Activity
    module_function

    # @return [Hash] { year:, total:, days: { "YYYY-MM-DD" => {count,input,output,cost_micros,models:[…]} },
    #                  models: [{model,count,input,output,cost_micros,up,down}, …], years: [Int,…] }
    def for_user(user, year:, plan_key: nil)
      year = year.to_i
      range = Time.zone.local(year, 1, 1).all_year

      rows = UsageEvent.where(user_id: user.id, created_at: range)
                       .group(Arel.sql("DATE(created_at)"), :model)
                       .pluck(
                         Arel.sql("DATE(created_at)"),
                         :model,
                         Arel.sql("COUNT(*)"),
                         Arel.sql("COALESCE(SUM(input_tokens), 0)"),
                         Arel.sql("COALESCE(SUM(output_tokens), 0)"),
                         Arel.sql("COALESCE(SUM(cost_micros), 0)")
                       )

      days = {}
      model_totals = Hash.new { |h, k| h[k] = { count: 0, input: 0, output: 0, cost_micros: 0 } }

      rows.each do |date, model, count, inp, out, cost|
        m = canonical_model(model)
        count = count.to_i; inp = inp.to_i; out = out.to_i; cost = cost.to_i

        day = days[date.to_s] ||= { count: 0, input: 0, output: 0, cost_micros: 0, models: {} }
        day[:count] += count; day[:input] += inp; day[:output] += out; day[:cost_micros] += cost
        dm = day[:models][m] ||= { count: 0, input: 0, output: 0, cost_micros: 0 }
        dm[:count] += count; dm[:input] += inp; dm[:output] += out; dm[:cost_micros] += cost

        t = model_totals[m]
        t[:count] += count; t[:input] += inp; t[:output] += out; t[:cost_micros] += cost
      end
      # Fold each day's per-model map into a count-sorted array.
      days.each_value { |d| d[:models] = d[:models].map { |mm, v| v.merge(model: mm) }.sort_by { |x| -x[:count] } }

      # Present the customer's OWN spend at RETAIL — the unit their balance is shown in. The ledger
      # stores what a request cost us at the wire; leaving that raw here made the dashboard understate
      # what the user actually spent (roughly by the margin), and put two different units on one page:
      # a retail-converted balance above, cost-denominated per-model rows below. Converted on the
      # AGGREGATES, so each figure rounds once rather than once per ledger row.
      #
      # plan_key nil leaves the raw COST figures alone, deliberately: an operator-side caller wants the
      # real COGS, not what the customer was charged. (The admin panel does not use this service today.)
      if plan_key
        days.each_value do |d|
          d[:cost_micros] = ::Levelcode.retail_micros(d[:cost_micros], plan_key)
          d[:models].each { |dm| dm[:cost_micros] = ::Levelcode.retail_micros(dm[:cost_micros], plan_key) }
        end
        model_totals.each_value { |v| v[:cost_micros] = ::Levelcode.retail_micros(v[:cost_micros], plan_key) }
      end

      fb = feedback_by_model(user, range)
      models = model_totals.map { |m, v| v.merge(model: m, up: fb.dig(m, "up").to_i, down: fb.dig(m, "down").to_i) }
                           .sort_by { |m| -m[:count] }

      {
        year: year,
        total: days.values.sum { |d| d[:count] },
        days: days,
        models: models,
        years: available_years(user)
      }
    end

    # Collapse a dated model snapshot to its base id (strip a trailing "-YYYYMMDD"/"-YYMMDD"),
    # so metering — which records the UPSTREAM-resolved model (e.g. "moonshotai/kimi-k2.7-code-20260612")
    # — and feedback — recorded against the REQUESTED id ("moonshotai/kimi-k2.7-code") — aggregate to the
    # same row. Non-dated ids (e.g. "openai/gpt-oss-120b") pass through unchanged.
    def canonical_model(model)
      (model.presence || "unknown").sub(/-\d{6,8}\z/, "")
    end

    # { canonical_model => { "up" => n, "down" => n } } — summed across raw model strings that
    # canonicalize to the same id.
    def feedback_by_model(user, range)
      UsageFeedback.where(user_id: user.id, created_at: range)
                   .group(:model, :rating)
                   .count
                   .each_with_object(Hash.new { |h, k| h[k] = Hash.new(0) }) do |((model, rating), n), acc|
        acc[canonical_model(model)][rating] += n
      end
    end

    # Descending list of years the user has any usage in (for the year picker); always
    # includes the current year so a brand-new user still sees a grid.
    def available_years(user)
      years = UsageEvent.where(user_id: user.id)
                        .distinct
                        .pluck(Arel.sql("EXTRACT(YEAR FROM created_at)::int"))
                        .map(&:to_i)
      (years + [ Time.current.year ]).uniq.sort.reverse
    end

    private_class_method :canonical_model, :feedback_by_model, :available_years
  end
end
