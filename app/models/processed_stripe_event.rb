# == Schema Information
#
# Table name: processed_stripe_events
#
#  id              :bigint           not null, primary key
#  event_type      :string           not null
#  processed_at    :datetime         not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  stripe_event_id :string           not null
#
# Indexes
#
#  index_processed_stripe_events_on_event_type       (event_type)
#  index_processed_stripe_events_on_processed_at     (processed_at)
#  index_processed_stripe_events_on_stripe_event_id  (stripe_event_id) UNIQUE
#
class ProcessedStripeEvent < ApplicationRecord
  validates :stripe_event_id, presence: true, uniqueness: true
  validates :event_type, presence: true
  validates :processed_at, presence: true

  # Clean up old events (optional - run as scheduled job)
  scope :older_than, ->(days) { where("processed_at < ?", days.days.ago) }

  def self.already_processed?(event_id)
    exists?(stripe_event_id: event_id)
  end

  def self.mark_as_processed!(event_id, event_type)
    create!(
      stripe_event_id: event_id,
      event_type: event_type,
      processed_at: Time.current
    )
  end
end
