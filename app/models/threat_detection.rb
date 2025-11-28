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
