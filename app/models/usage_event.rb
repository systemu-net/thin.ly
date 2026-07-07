# == Schema Information
#
# Table name: usage_events
#
#  id                  :bigint           not null, primary key
#  cached_input_tokens :bigint           default(0), not null
#  cost_micros         :bigint           default(0), not null
#  input_tokens        :bigint           default(0), not null
#  model               :string
#  output_tokens       :bigint           default(0), not null
#  provider            :string
#  created_at          :datetime         not null
#  request_id          :string
#  user_id             :bigint           not null
#
# Indexes
#
#  index_usage_events_on_request_id_unique       (request_id) UNIQUE WHERE (request_id IS NOT NULL)
#  index_usage_events_on_user_id                 (user_id)
#  index_usage_events_on_user_id_and_created_at  (user_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class UsageEvent < ApplicationRecord
  belongs_to :user

  validates :input_tokens, :output_tokens, :cached_input_tokens, :cost_micros,
            numericality: { greater_than_or_equal_to: 0 }

  # Total input tokens including the cached subset (mirrors upstream usage).
  def total_input_tokens
    input_tokens
  end

  # Cost expressed in whole dollars (micros → dollars) for display/analytics.
  def cost_dollars
    cost_micros / 1_000_000.0
  end
end
