# == Schema Information
#
# Table name: link_routing_rules
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  conditions      :jsonb
#  destination_url :string           not null
#  priority        :integer          default(0), not null
#  rule_type       :string           not null
#  weight          :integer
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  link_id         :bigint           not null
#
# Indexes
#
#  index_link_routing_rules_on_link_id               (link_id)
#  index_link_routing_rules_on_link_id_and_priority  (link_id,priority)
#
# Foreign Keys
#
#  fk_rails_...  (link_id => links.id)
#
class LinkRoutingRule < ApplicationRecord
  RULE_TYPES = %w[geo device referrer time_window percentage].freeze

  belongs_to :link

  validates :rule_type, inclusion: { in: RULE_TYPES }
  validates :destination_url, presence: true
  validates :weight, numericality: { in: 1..100 }, if: -> { rule_type == "percentage" }
  validate  :destination_url_format

  scope :active, -> { where(active: true) }

  private

  def destination_url_format
    uri = URI.parse(destination_url)
    errors.add(:destination_url, "must be a valid URL") if uri.host.nil?
  rescue URI::InvalidURIError
    errors.add(:destination_url, "is not a valid URL")
  end
end
