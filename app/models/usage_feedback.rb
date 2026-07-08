# frozen_string_literal: true

# == Schema Information
#
# Table name: usage_feedbacks
#
#  id         :bigint           not null, primary key
#  model      :string
#  rating     :string           not null
#  created_at :datetime         not null
#  request_id :string
#  user_id    :bigint           not null
#
# Indexes
#
#  index_usage_feedbacks_on_user_id                 (user_id)
#  index_usage_feedbacks_on_user_id_and_created_at  (user_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class UsageFeedback < ApplicationRecord
  belongs_to :user

  RATINGS = %w[up down].freeze

  validates :rating, inclusion: { in: RATINGS }
end
