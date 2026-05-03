# == Schema Information
#
# Table name: link_governance_logs
#
#  id           :bigint           not null, primary key
#  action       :string           not null
#  after_state  :jsonb
#  before_state :jsonb
#  ip_address   :string
#  reason       :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  link_id      :bigint           not null
#  user_id      :bigint
#
# Indexes
#
#  index_link_governance_logs_on_link_id                 (link_id)
#  index_link_governance_logs_on_link_id_and_created_at  (link_id,created_at)
#  index_link_governance_logs_on_user_id                 (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (link_id => links.id)
#  fk_rails_...  (user_id => users.id)
#
class LinkGovernanceLog < ApplicationRecord
  ACTIONS = %w[
    state_change destination_update rule_added rule_updated
    rule_removed campaign_assigned campaign_changed password_toggled
  ].freeze

  belongs_to :link
  belongs_to :user, optional: true  # nil = system/automated action

  validates :action, presence: true
end
