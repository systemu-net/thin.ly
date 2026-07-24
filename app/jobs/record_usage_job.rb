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
#   - The row is DATED from `occurred_at_epoch` (when the request ran), not from when
#     this job happens to execute — so a backed-up queue cannot rewrite usage history.
#
# Enqueued as: RecordUsageJob.perform_async(user_id, request_id, model, provider,
#   input_tokens, output_tokens, cached_input_tokens, cost_micros, period_end_epoch,
#   occurred_at_epoch).
# The last two are optional and trailing so jobs serialized by an older deploy still run.
class RecordUsageJob
  include Sidekiq::Job
  queue_as :default

  # occurred_at_epoch is LAST and optional on purpose: jobs already sitting in the queue were
  # serialized with the old arity, so a deploy of this change must not make them fail.
  def perform(user_id, request_id, model, provider, input_tokens, output_tokens, cached_input_tokens, cost_micros, period_end_epoch = nil, occurred_at_epoch = nil)
    request_id = SecureRandom.uuid if request_id.blank? # never collapse blanks onto one row

    event = UsageEvent.create_or_find_by!(request_id: request_id) do |e|
      e.assign_attributes(
        user_id: user_id,
        model: model,
        provider: provider,
        input_tokens: input_tokens.to_i,
        output_tokens: output_tokens.to_i,
        cached_input_tokens: cached_input_tokens.to_i,
        cost_micros: cost_micros.to_i,
        # Date the row from WHEN THE REQUEST HAPPENED, not when this job finally ran. Without this, any
        # queue lag silently rewrites history: during the 2026-07-22 worker outage 141 jobs backed up,
        # and draining them would have stamped every one with the recovery moment — a false spike on the
        # recovery day and a permanent hole on the days the work was actually done.
        created_at: occurred_at_epoch.present? ? Time.zone.at(occurred_at_epoch.to_i) : Time.current
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
