# frozen_string_literal: true

module Levelcode
  # Referral funnel for the admin dashboard: clicks -> signups -> paid, per marketing channel.
  #
  # The three numbers come from three unrelated places and are joined ONLY by channel name, so
  # read the caveats before trusting a row:
  #
  #   clicks   `clicks` joined to `links`, channel parsed out of `links.original_url`. A click row
  #            carries no destination of its own, so a link whose destination is later edited
  #            re-attributes all of its past clicks. Bots are excluded (Click.human_traffic).
  #   signups  `users.signup_attribution->>'source'`, date-filtered on users.created_at. Only
  #            LevelCode writes that column, so it needs no extra product scoping.
  #   paid     a LevelCode credit_wallet that is currently on a paid plan. There is NO
  #            "became paid at" timestamp in the schema, so this is necessarily "signed up in
  #            range AND is paying now" — not "converted during the range". The API says so in
  #            `paid_basis` and the dashboard repeats it, because the difference matters when
  #            someone reads the column as a conversion rate.
  #
  # A click and a signup can never be joined per-person: clicks are anonymous.
  module ReferralReport
    module_function

    PRODUCT = "levelcode"

    # Mirrors the SPA's attribution util (onetime/src/levelcode/attribution.ts) — same keys, same
    # precedence, so a link's channel and a signup's `source` agree on a name.
    PARAM_KEYS = %w[linkedin youtube ref utm_source utm_medium utm_campaign utm_content].freeze

    # Only links that actually point at the product count as marketing links. There is no flag on
    # `links` marking one, so the destination HOST is the only available selector.
    #
    # Anchored on scheme + host rather than a substring: `ILIKE '%levelcode.ai%'` also matches
    # `https://notlevelcode.ai/?linkedin=x` and `https://evil.test/?next=levelcode.ai`, and since
    # anyone can shorten any URL, that is an open door to inflating a partner's click count.
    # Subdomains are allowed (www. and friends); the host must END there, so a lookalike like
    # `levelcode.ai.evil.test` does not match.
    MARKETING_URL_REGEX = '^https?://([a-z0-9_-]+\.)*levelcode\.ai(:[0-9]+)?([/?#]|$)'

    # Derive the channel from a link's destination, in the SPA's precedence order: a named network
    # wins, then utm_source, then ref. Anything else is "other".
    CHANNEL_SQL = Arel.sql(<<~SQL.squish)
      CASE
        WHEN links.original_url ~ '[?&]linkedin='    THEN 'linkedin'
        WHEN links.original_url ~ '[?&]youtube='     THEN 'youtube'
        WHEN links.original_url ~ '[?&]utm_source='  THEN substring(links.original_url from '[?&]utm_source=([^&#]+)')
        WHEN links.original_url ~ '[?&]ref='         THEN substring(links.original_url from '[?&]ref=([^&#]+)')
        ELSE 'other'
      END
    SQL

    # The partner handle behind the channel — the value of whichever param matched above.
    HANDLE_SQL = Arel.sql(<<~SQL.squish)
      COALESCE(
        substring(links.original_url from '[?&]linkedin=([^&#]+)'),
        substring(links.original_url from '[?&]youtube=([^&#]+)'),
        substring(links.original_url from '[?&]ref=([^&#]+)'),
        ''
      )
    SQL

    # One row per (channel, handle) with the three funnel numbers, plus totals and the counts that
    # explain what the table is NOT showing.
    #
    # `from` / `to` are Dates (inclusive). `to` is expanded to the end of that day.
    def funnel(from: nil, to: nil)
      range = date_range(from, to)

      clicks   = clicks_by_channel(range)
      signups  = signups_by_channel(range)
      paid     = paid_by_channel(range)

      rows = (clicks.keys | signups.keys | paid.keys).map do |key|
        channel, handle = key
        {
          channel: channel,
          handle: handle.presence,
          clicks: clicks[key].to_i,
          signups: signups[key].to_i,
          paid: paid[key].to_i
        }
      end
      rows.sort_by! { |r| [ -r[:signups], -r[:clicks], r[:channel].to_s ] }

      {
        from: range.begin.to_date.iso8601,
        to: range.end.to_date.iso8601,
        rows: rows,
        totals: {
          clicks: rows.sum { |r| r[:clicks] },
          signups: rows.sum { |r| r[:signups] },
          paid: rows.sum { |r| r[:paid] }
        },
        # Signups in range with no channel at all: organic, or a referred visitor whose browser
        # dropped the stored attribution. Shown so the table is never mistaken for total signups.
        unattributed_signups: User.where(created_at: range, signup_attribution: nil).count,
        # "Paid" is a snapshot, not an event — see the note at the top of this file.
        paid_basis: "signed_up_in_range_and_paying_now"
      }
    end

    # --- pieces ---------------------------------------------------------------

    # Human clicks in range on links whose destination points at the product, grouped by the
    # channel + handle encoded in that destination.
    def clicks_by_channel(range)
      Click.human_traffic
           .joins(:link)
           .where(created_at: range)
           .where("links.original_url ~* ?", MARKETING_URL_REGEX)
           .group(CHANNEL_SQL, HANDLE_SQL)
           .count
    end

    # Signups in range that carried a channel. The handle is the value of the param the source
    # names, so `{"source":"linkedin","params":{"linkedin":"anastasia"}}` lands in the same bucket
    # as the link that produced the click.
    def signups_by_channel(range)
      User.where(created_at: range)
          .where.not(signup_attribution: nil)
          .group(source_sql, handle_sql)
          .count
    end

    # Of those signups, the ones on a paid LevelCode plan right now. Mirrors the predicate in
    # Levelcode::FreeTier.paid? (which is private), including its 3-day grace on a lapsed period
    # so a renewal in flight does not read as a downgrade.
    def paid_by_channel(range)
      User.where(created_at: range)
          .where.not(signup_attribution: nil)
          .joins("INNER JOIN credit_wallets ON credit_wallets.user_id = users.id")
          .where(credit_wallets: { product: PRODUCT })
          .where.not(credit_wallets: { plan_key: ::Levelcode::FREE_PLAN_KEY })
          .where("credit_wallets.budget_micros > 0")
          .where("credit_wallets.period_end IS NULL OR credit_wallets.period_end >= ?", Time.current - 3.days)
          .group(source_sql, handle_sql)
          .count
    end

    # --- helpers --------------------------------------------------------------

    def source_sql
      Arel.sql("users.signup_attribution->>'source'")
    end

    # The handle for a signup: the params value named by `source`. COALESCE rather than a lookup
    # because `source` may be a raw utm_source/ref value with no matching params key.
    def handle_sql
      Arel.sql(<<~SQL.squish)
        COALESCE(
          users.signup_attribution->'params'->>(users.signup_attribution->>'source'),
          users.signup_attribution->'params'->>'ref',
          ''
        )
      SQL
    end

    # Inclusive day range, defaulting to the last 30 days. Guards a reversed pair so a mis-typed
    # filter returns an empty range rather than a Postgres error.
    def date_range(from, to)
      finish = (to.presence && to.to_date) || Date.current
      start  = (from.presence && from.to_date) || (finish - 29)
      start  = finish if start > finish
      start.beginning_of_day..finish.end_of_day
    end

    private_class_method :clicks_by_channel, :signups_by_channel, :paid_by_channel,
                         :source_sql, :handle_sql, :date_range
  end
end
