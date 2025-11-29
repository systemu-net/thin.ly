# == Schema Information
#
# Table name: threat_detections
#
#  id              :bigint           not null, primary key
#  detectable_type :string           not null
#  notes           :text
#  platform_types  :json
#  resolved_at     :datetime
#  severity        :string
#  status          :string           default("active")
#  threat_types    :json
#  url             :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  detectable_id   :bigint           not null
#
# Indexes
#
#  idx_on_detectable_type_detectable_id_status_ac4e47f857  (detectable_type,detectable_id,status)
#  index_threat_detections_on_created_at                   (created_at)
#  index_threat_detections_on_detectable                   (detectable_type,detectable_id)
#  index_threat_detections_on_status                       (status)
#
class ThreatDetection < ApplicationRecord
  belongs_to :detectable, polymorphic: true

  validates :url, :threat_types, presence: true
  validates :status, inclusion: { in: %w[active resolved false_positive] }
  validates :severity, inclusion: { in: %w[HIGH MEDIUM LOW] }, allow_nil: true

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :resolved, -> { where(status: "resolved") }
  scope :unresolved, -> { where(status: "active") }
  scope :high_severity, -> { where(severity: "HIGH") }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where("threat_types @> ?", [ type ].to_json) }

  # Mark as resolved
  def resolve!(notes: nil)
    update!(
      status: "resolved",
      resolved_at: Time.current,
      notes: notes
    )
  end

  # Mark as false positive
  def mark_false_positive!(notes: nil)
    update!(
      status: "false_positive",
      resolved_at: Time.current,
      notes: notes
    )
  end

  # Human-readable threat types
  def threat_types_humanized
    threat_types.map { |t| t.titleize.gsub("_", " ") }.join(", ")
  end
end
