# frozen_string_literal: true

module Levelcode
  # Aggregations for the admin dashboard (admin-only). System-wide token/request totals and a
  # per-user roll-up (tokens burned, requests, plan, country, auth attempts) that the admin can
  # sort/filter to find the heaviest users and spot login problems. Each metric is one grouped
  # query; the per-user list is assembled in Ruby (fine at current scale — revisit with pagination
  # pushed into SQL if the user table grows large).
  module AdminReport
    module_function

    PRODUCT = "levelcode"
    SORTS = %w[input output requests cost last_seen auth_attempts auth_failures email plan created].freeze
    # Postgres FILTER aggregate — count only the failed attempts in the same pass.
    FAIL_FILTER = Arel.sql("COUNT(*) FILTER (WHERE outcome = 'failure')")

    # System-wide totals + plan/country/auth breakdowns for the summary cards.
    def summary
      u = UsageEvent.pick(
        Arel.sql("COALESCE(SUM(input_tokens), 0)"),
        Arel.sql("COALESCE(SUM(output_tokens), 0)"),
        Arel.sql("COUNT(*)"),
        Arel.sql("COALESCE(SUM(cost_micros), 0)")
      ) || [ 0, 0, 0, 0 ]
      a = AuthEvent.pick(Arel.sql("COUNT(*)"), FAIL_FILTER) || [ 0, 0 ]

      {
        users: User.count,
        active_users: UsageEvent.distinct.count(:user_id),
        input: u[0].to_i,
        output: u[1].to_i,
        requests: u[2].to_i,
        cost_micros: u[3].to_i,
        plans: plan_counts,
        countries: User.where.not(last_country: nil).group(:last_country).count,
        auth_attempts: a[0].to_i,
        auth_failures: a[1].to_i,
        auth_failures_by_country: AuthEvent.failures.where.not(country: nil).group(:country).count
      }
    end

    # Per-user roll-up, sorted + filtered + paginated.
    def users(sort: "input", dir: "desc", q: nil, plan: nil, limit: 100, offset: 0)
      rows = enriched_users
      rows = rows.select { |r| r[:email].to_s.include?(q.to_s.strip.downcase) } if q.present?
      rows = rows.select { |r| r[:plan] == plan } if plan.present?

      key = SORTS.include?(sort.to_s) ? sort.to_s : "input"
      rows = rows.sort_by { |r| sort_value(r, key) }
      rows.reverse! unless dir.to_s == "asc"

      { total: rows.size, limit: limit, offset: offset, users: rows[offset, limit] || [] }
    end

    # --- internals -----------------------------------------------------------

    def enriched_users
      usage = UsageEvent.group(:user_id).pluck(
        :user_id,
        Arel.sql("COALESCE(SUM(input_tokens), 0)"),
        Arel.sql("COALESCE(SUM(output_tokens), 0)"),
        Arel.sql("COUNT(*)"),
        Arel.sql("COALESCE(SUM(cost_micros), 0)")
      ).each_with_object({}) { |(uid, i, o, r, c), h| h[uid] = [ i.to_i, o.to_i, r.to_i, c.to_i ] }

      auth = AuthEvent.where.not(user_id: nil).group(:user_id).pluck(:user_id, Arel.sql("COUNT(*)"), FAIL_FILTER)
                      .each_with_object({}) { |(uid, n, f), h| h[uid] = [ n.to_i, f.to_i ] }

      wallets = CreditWallet.where(product: PRODUCT).pluck(:user_id, :plan_key).to_h

      # Enrich only the ACTIVE set — users who have usage, an auth event, or a wallet — since every
      # admin metric (tokens/requests/plan/country/auth) is about users who did something. This bounds
      # the Ruby materialization to active users instead of every signup (the grouped aggregates above
      # are DB-side and already return one row per active user).
      ids = (usage.keys + auth.keys + wallets.keys).uniq
      User.where(id: ids).pluck(:id, :email, :role, :last_country, :last_seen_at, :created_at).map do |id, email, role, country, seen, created|
        us = usage[id] || [ 0, 0, 0, 0 ]
        au = auth[id] || [ 0, 0 ]
        {
          id: id, email: email, role: role, plan: plan_label(wallets[id]),
          input: us[0], output: us[1], requests: us[2], cost_micros: us[3],
          country: country, last_seen_at: seen,
          auth_attempts: au[0], auth_failures: au[1], created_at: created
        }
      end
    end

    def sort_value(row, key)
      case key
      when "email", "plan" then row[key.to_sym].to_s
      when "last_seen"     then row[:last_seen_at]&.to_i || 0
      when "created"       then row[:created_at]&.to_i || 0
      else row[key.to_sym].to_i # input/output/requests/cost/auth_attempts/auth_failures
      end
    end

    def plan_counts
      CreditWallet.where(product: PRODUCT).group(:plan_key).count
                  .each_with_object(Hash.new(0)) { |(k, n), h| h[plan_label(k)] += n }
    end

    def plan_label(key)
      k = key.to_s
      return "Free" if k.blank? || k == Levelcode::FREE_PLAN_KEY

      Levelcode.plan(k)&.dig(:name) || k
    end

    private_class_method :enriched_users, :sort_value, :plan_counts, :plan_label
  end
end
