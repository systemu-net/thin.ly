class AddUniqueIndexToUsageEventsRequestId < ActiveRecord::Migration[7.2]
  # Partial unique index: enforce one usage_events row per request_id (idempotent
  # RecordUsageJob via create_or_find_by!), while still allowing NULL request_ids.
  def change
    add_index :usage_events, :request_id,
              unique: true,
              where: "request_id IS NOT NULL",
              name: "index_usage_events_on_request_id_unique"
  end
end
