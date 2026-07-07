# frozen_string_literal: true

# == Schema Information
#
# Table name: auth_events
#
#  id         :bigint           not null, primary key
#  country    :string
#  email      :string
#  ip         :string
#  kind       :string           not null
#  outcome    :string           not null
#  provider   :string
#  reason     :string
#  created_at :datetime         not null
#  user_id    :bigint
#
# Indexes
#
#  index_auth_events_on_created_at  (created_at)
#  index_auth_events_on_email       (email)
#  index_auth_events_on_outcome     (outcome)
#  index_auth_events_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class AuthEvent < ApplicationRecord
  belongs_to :user, optional: true

  KINDS    = %w[email oauth exchange login refresh].freeze
  OUTCOMES = %w[success failure].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :outcome, inclusion: { in: OUTCOMES }

  scope :failures, -> { where(outcome: "failure") }
  scope :successes, -> { where(outcome: "success") }
end
