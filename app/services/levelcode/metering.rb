module Levelcode
  # Redis hot-counter metering + pre-request enforcement (SPEC §5).
  #
  # Counters live at `levelcode:used:{user}:{period}:{in|out}` and are the fast
  # path consulted before each request; the durable ledger (usage_events) is
  # written off-request by RecordUsageJob. All Redis access is fail-open: if
  # Redis is down we warn and let the request through rather than hard-blocking
  # a paying user on an infra hiccup.
  module Metering
    module_function

    # Orphaned per-period counter keys (the key embeds period_end) would otherwise
    # live forever; expire them well past any billing period so they self-clean.
    COUNTER_TTL = 60 * 24 * 60 * 60 # 60 days

    # Result of a pre-request check. `allowed` false ⇒ caller must 402.
    # `throttle` true ⇒ caller forces the small model. `policy` echoes the
    # wallet's overage_policy for building the error payload.
    Decision = Struct.new(:allowed, :throttle, :policy, keyword_init: true) do
      def blocked?
        !allowed
      end
    end

    # Result of an admission-time budget reservation (M14 concurrency guard). `ok` false ⇒ the request
    # would push spend past the budget and must 402. `amount` is the micro-$ reserved (0 when nothing
    # was reserved: a non-positive estimate, or a fail-open Redis error) — pass it back to settle!.
    Reservation = Struct.new(:ok, :amount, keyword_init: true)

    # Decide whether/how to serve the request against the wallet's DOLLAR budget (M14). Compares the
    # micro-$ spent this period (Redis hot counter) to budget_micros. Fail-open on Redis errors.
    def check!(wallet)
      # No budget ⇒ no active managed plan (BYOK / canceled / unprovisioned). BLOCK — a zero budget
      # is NOT "unlimited". This must come before any fail-open Redis path.
      if wallet.budget_micros.to_i <= 0
        return Decision.new(allowed: false, throttle: false, policy: "stop")
      end

      # spent_micros falls back to the DURABLE wallet.spent_micros if Redis is down — so an
      # over-budget hard-stop wallet stays blocked through an outage, while an under-budget wallet
      # still passes (no paying user blocked on infra noise).
      decide(over_budget?(spent_micros(wallet), wallet), wallet)
    end

    # The dollar ceiling ENFORCED right now. Normally the wallet's full budget_micros, but when
    # tranching is enabled (Levelcode::BUDGET_TRANCHES > 1) it rises in N equal steps from budget/N up
    # to the full budget across the billing period (window = period / N): a heavy user can't front-load
    # the whole month, while a light user stays under the rising ceiling and never notices. Pure
    # function of the wallet + now — no state, no cron. Monotonic non-decreasing and capped at the full
    # budget, so total served spend can NEVER exceed the budget (the margin guarantee). Spend tracking
    # (the Redis counter / durable spent_micros) is untouched — a tranche unlock must never reset spend.
    def unlocked_budget_micros(wallet, now = Time.current)
      full = wallet.budget_micros.to_i
      n    = Levelcode::BUDGET_TRANCHES
      return full if full <= 0 || n <= 1                # disabled, or no managed plan (0)
      return full if wallet.plan_key == FREE_PLAN_KEY   # NEVER tranche the free tier

      start = wallet.period_start || wallet.created_at
      fin   = wallet.period_end
      return full if start.blank? || fin.blank? || fin <= start

window  = (fin - start).to_f / n                  # seconds; derived from the REAL period length
return full if window <= 0.0
elapsed = [ (now - start).to_f, 0.0 ].max         # clamp clock-skew / future start → k = 1
k = (1 + (elapsed / window).floor).clamp(1, n)
(full * k) / n                                    # integer micro-$; == full EXACTLY at k == n
    end

    # True when this period's spend has reached the currently-unlocked dollar ceiling.
    def over_budget?(spent, wallet)
      spent >= unlocked_budget_micros(wallet)
    end

    # Map (over_cap?, policy) → a Decision. Under cap: allow. Over cap: throttle
    # forces the small model (allowed); topup/stop 402 (the controller shapes the body).
    def decide(over_cap, wallet)
      return Decision.new(allowed: true, throttle: false, policy: wallet.overage_policy) unless over_cap

      case wallet.overage_policy
      when "throttle"
        Decision.new(allowed: true, throttle: true, policy: "throttle")
      else # "topup" or "stop" — both 402; the controller differentiates the body
        Decision.new(allowed: false, throttle: false, policy: wallet.overage_policy)
      end
    end

    # Increment the hot counters once the final usage is known: input/output tokens (informational)
    # AND the micro-$ SPEND (the enforced budget). Fail-open. Durable per-period totals live in the
    # CreditWallet columns (kept in sync by RecordUsageJob); these Redis counters are the fast cache.
    def record(wallet, input_tokens, output_tokens, cost_micros = 0)
      input_tokens = input_tokens.to_i
      output_tokens = output_tokens.to_i
      cost_micros = cost_micros.to_i
      return if input_tokens.zero? && output_tokens.zero? && cost_micros.zero?

      redis.pipelined do |pipe|
        pipe.incrby(key(wallet, "in"), input_tokens)
        pipe.incrby(key(wallet, "out"), output_tokens)
        pipe.incrby(key(wallet, "spent"), cost_micros)
        pipe.expire(key(wallet, "in"), COUNTER_TTL)
        pipe.expire(key(wallet, "out"), COUNTER_TTL)
        pipe.expire(key(wallet, "spent"), COUNTER_TTL)
      end
      true
    rescue => e
      warn_redis(e)
      false
    end

    # Reserve `estimate_micros` of budget for an IN-FLIGHT request, atomically, so CONCURRENT
    # admissions see each other's reservations and can't collectively overshoot the dollar budget
    # (the check!-then-record window: spend only lands after a stream closes). INCRBYs the hot spend
    # counter up-front; if that tips total spend past the budget, it rolls the reservation back and
    # returns ok:false (caller must 402). Fail-open on Redis error (allow, amount 0) so a paying user
    # isn't blocked on an infra blip — the durable ledger still records the real spend afterward.
    def reserve!(wallet, estimate_micros)
      estimate_micros = estimate_micros.to_i
      return Reservation.new(ok: true, amount: 0) if estimate_micros <= 0

      k = key(wallet, "spent")
      new_spent = redis.incrby(k, estimate_micros) # the reservation is now on the counter
      begin
        redis.expire(k, COUNTER_TTL)
      rescue => e
        # TTL is best-effort; the reservation still stands, so we must fall through and RETURN its
        # amount so settle! subtracts it later (returning 0 here would strand the estimate).
        warn_redis(e)
      end

      if new_spent > unlocked_budget_micros(wallet)
        begin
          redis.incrby(k, -estimate_micros) # roll back — this request doesn't fit the remaining budget
        rescue => e
          warn_redis(e) # rollback is best-effort; a stranded estimate over-counts (safe direction, TTL'd)
        end
        return Reservation.new(ok: false, amount: 0)
      end
      Reservation.new(ok: true, amount: estimate_micros)
    rescue => e
      # The reserving INCRBY itself failed → nothing landed on the counter → fail open (no reservation).
      warn_redis(e)
      Reservation.new(ok: true, amount: 0)
    end

    # Reconcile a reservation to the ACTUAL spend once the request settles. The hot counter already
    # holds `reserved_micros` (from reserve!), so adjust it by (actual − reserved) to land on the real
    # spend; with no reservation (throttle / fail-open path) just add the actual. Always bumps the
    # informational input/output token counters too. Fail-open.
    def settle!(wallet, reserved_micros, input_tokens, output_tokens, actual_micros)
      reserved_micros = reserved_micros.to_i
      actual_micros   = actual_micros.to_i
      input_tokens    = input_tokens.to_i
      output_tokens   = output_tokens.to_i
      delta = actual_micros - reserved_micros
      return true if delta.zero? && input_tokens.zero? && output_tokens.zero?

      unless delta.zero?
        spent_key = key(wallet, "spent")
        new_spent = redis.incrby(spent_key, delta)
        # A same-epoch reset (clear!) or eviction between reserve! and here can leave the estimate OFF
        # the counter, so a negative delta would drive it below zero and mask real spend against the
        # budget — floor it at 0. (spent_micros also floors defensively for the same reason.)
        redis.set(spent_key, 0) if new_spent.to_i.negative?
        redis.expire(spent_key, COUNTER_TTL)
      end

      unless input_tokens.zero? && output_tokens.zero?
        redis.pipelined do |pipe|
          pipe.incrby(key(wallet, "in"), input_tokens) unless input_tokens.zero?
          pipe.incrby(key(wallet, "out"), output_tokens) unless output_tokens.zero?
          pipe.expire(key(wallet, "in"), COUNTER_TTL)
          pipe.expire(key(wallet, "out"), COUNTER_TTL)
        end
      end
      true
    rescue => e
      warn_redis(e)
      false
    end

    # Best-effort wipe of the current period's hot counters (spend/in/out). Used when usage is RESET
    # for a period that reuses the same period_end epoch — otherwise spent_micros = max(Redis, durable)
    # would resurrect the pre-reset spend from the stale hot counter. Fail-open.
    def clear!(wallet)
      redis.del(key(wallet, "spent"), key(wallet, "in"), key(wallet, "out"))
      true
    rescue => e
      warn_redis(e)
      false
    end

    # Micro-$ spent this period, for enforcement. Takes the MAX of the live Redis counter and the
    # durable wallet.spent_micros — always enforcing on whichever shows MORE spend. This closes the
    # money-direction fail-open where the Redis counter UNDERCOUNTS while Redis is up and answering:
    #   - a lost INCRBY during a prior Redis outage (record() fail-opens; the durable ledger still
    #     bumps via RecordUsageJob),
    #   - an LRU eviction / cold-replica failover / FLUSHDB (GET misses → 0),
    #   - a period_end re-anchor (mid-cycle plan change) orphaning the old key (GET on the new key
    #     misses → 0) while spent_micros is deliberately preserved.
    # In steady state the Redis counter leads (the durable column lags the async job), so max == Redis;
    # when Redis is behind/empty, max == the durable column → an over-budget wallet stays blocked and
    # spend is never refunded. It's a MAX, not a sum, so it never double-counts.
    def spent_micros(wallet)
      # Floor the hot counter at 0 first: a reconcile after a mid-flight reset/eviction can briefly
      # leave it negative, and a negative value must never suppress enforcement BELOW the durable spend.
      [ [ redis.get(key(wallet, "spent")).to_i, 0 ].max, wallet.spent_micros.to_i ].max
    rescue => e
      warn_redis(e)
      wallet.spent_micros.to_i
    end

    # Live per-period token usage [input, output] for the account dashboard (informational).
    # Falls back to the durable wallet columns if Redis is unavailable.
    def usage(wallet)
      current_usage(wallet)
    rescue => e
      warn_redis(e)
      [ wallet.input_used.to_i, wallet.output_used.to_i ]
    end

    # -- internals ------------------------------------------------------------

    def current_usage(wallet)
      values = redis.mget(key(wallet, "in"), key(wallet, "out"))
      [ values[0].to_i, values[1].to_i ]
    end

    def key(wallet, direction)
      "levelcode:used:#{wallet.user_id}:#{period(wallet)}:#{direction}"
    end

    # A stable per-billing-period token so counters roll over with the wallet.
    def period(wallet)
      wallet.period_end&.to_i || wallet.period_start&.to_i || "current"
    end

    def redis
      $redis
    end

    def warn_redis(error)
      Rails.logger.warn("[Levelcode::Metering] Redis unavailable, degrading gracefully: #{error.class}: #{error.message}")
      StatsD.increment("orbits.metering.redis_error") if defined?(StatsD)
    end

    private_class_method :over_budget?, :decide, :current_usage, :key, :period, :redis, :warn_redis
  end
end
