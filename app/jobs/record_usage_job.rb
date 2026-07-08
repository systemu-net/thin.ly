require "sidekiq"

# Writes the durable usage ledger row (usage_events) off the request path AND
# keeps the per-period CreditWallet counter in sync (SPEC §5).
#
# Idempotent + period-safe:
#   - `request_id` is unique (partial unique index), so a Sidekiq retry or a
#     duplicate enqueue neither inserts a second ledger row nor double-increments
#     the wallet counters (the bump runs only on the first insert).
#   - The wallet increment is scoped to the billing period captured at ENQUEUE
#     time (`period_end_epoch`), so a late job for an already-rolled period no-ops
#     instead of corrupting the new period's totals.
#
# Enqueued as: RecordUsageJob.perform_async(user_id, request_id, model, provider,
#   input_tokens, output_tokens, cached_input_tokens, cost_micros, period_end_epoch).
class RecordUsageJob
  include Sidekiq::Job
  queue_as :default

  def perform(user_id, request_id, model, provider, input_tokens, output_tokens, cached_input_tokens, cost_micros, period_end_epoch = nil)
    request_id = SecureRandom.uuid if request_id.blank? # never collapse blanks onto one row

    event = UsageEvent.create_or_find_by!(request_id: request_id) do |e|
      e.assign_attributes(
        user_id: user_id,
        model: model,
        provider: provider,
        input_tokens: input_tokens.to_i,
        output_tokens: output_tokens.to_i,
        cached_input_tokens: cached_input_tokens.to_i,
        cost_micros: cost_micros.to_i
      )
    end

    # Only bump the durable per-period counter on the FIRST (unique) ledger insert,
    # and only against the wallet still in the SAME period as when this was enqueued.
    return unless event.previously_new_record?

    # FLOOR both sides so the match survives a fractional-second period_end. The enqueue passes
    # `wallet.period_end.to_i` (Ruby Time#to_i TRUNCATES to whole seconds), but a bare
    # `EXTRACT(EPOCH FROM period_end)::bigint` ROUNDS to nearest — so a period_end stored with ≥ .5µs
    # rounds UP and never equals the truncated arg, silently matching 0 rows (the durable columns then
    # freeze at 0 while only the Redis counter — which floors on both sides — stays correct).
    CreditWallet
      .where(user_id: user_id, product: Levelcode::PRODUCT)
      .where("period_end IS NOT NULL AND FLOOR(EXTRACT(EPOCH FROM period_end))::bigint = ?", period_end_epoch.to_i)
      .update_all([
        "input_used = input_used + ?, output_used = output_used + ?, spent_micros = spent_micros + ?, updated_at = ?",
        input_tokens.to_i, output_tokens.to_i, cost_micros.to_i, Time.current
      ])
  end
end
