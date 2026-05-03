# Extracted from Link to keep governance logic isolated and testable.
# Include in Link model via `include LinkGovernance`.
module LinkGovernance
  extend ActiveSupport::Concern

  STATES = %w[draft active paused expired archived].freeze

  included do
    belongs_to :link_campaign, optional: true
    has_many :routing_rules, class_name: "LinkRoutingRule", dependent: :destroy
    has_many :governance_logs, class_name: "LinkGovernanceLog", dependent: :destroy
    has_many :destination_histories, class_name: "LinkDestinationHistory", dependent: :destroy

    validates :state, inclusion: { in: STATES }

    before_update :log_destination_change, if: :will_save_change_to_original_url?
    after_create  :record_initial_destination

    scope :active_now, -> {
      where(state: "active")
        .where("activates_at IS NULL OR activates_at <= ?", Time.current)
    }
    scope :expiring_soon, -> {
      where(state: "active")
        .where("expires_at BETWEEN ? AND ?", Time.current, 24.hours.from_now)
    }
    scope :governed, -> { where(governance_enabled: true) }
  end

  # ── Public API ──────────────────────────────────────────────────────────

  # Resolve the final destination for a click, applying governance rules.
  # Returns a URL string. The `context` hash carries request metadata:
  #   { country:, device_type:, referrer:, timestamp: }
  def resolve_destination(context = {})
    return governance_redirect(:paused)  if paused?
    return governance_redirect(:expired) if expired_or_over_cap?
    return original_url unless governance_enabled?

    # Evaluate routing rules (ordered by priority, first match wins)
    active_rules = routing_rules.where(active: true).order(:priority)
    if active_rules.any?
      matched = RoutingRulesEngine.evaluate(active_rules, context)
      return matched.destination_url if matched
    end

    original_url
  end

  # Transition the link to a new lifecycle state with a full audit entry.
  def transition_to!(new_state, user: nil, reason: nil, ip_address: nil)
    raise ArgumentError, "Invalid state: #{new_state}" unless STATES.include?(new_state)

    old_state = state
    update!(state: new_state)
    governance_logs.create!(
      user: user,
      action: "state_change",
      before_state: { state: old_state },
      after_state: { state: new_state },
      reason: reason,
      ip_address: ip_address
    )
  end

  # Swap the destination URL and maintain a full history trail.
  def update_destination!(new_url, user: nil, reason: nil, ip_address: nil)
    old_url = original_url
    transaction do
      destination_histories.where(active_until: nil).update_all(active_until: Time.current)
      destination_histories.create!(destination_url: new_url, active_from: Time.current)
      # Use update_columns to skip callbacks (the before_update would double-log)
      update_columns(original_url: new_url, updated_at: Time.current)
      governance_logs.create!(
        user: user,
        action: "destination_update",
        before_state: { destination_url: old_url },
        after_state: { destination_url: new_url },
        reason: reason,
        ip_address: ip_address
      )
    end
  end

  # ── State predicates ────────────────────────────────────────────────────

  def draft?    = state == "draft"
  def active?   = state == "active"
  def paused?   = state == "paused"
  def expired?  = state == "expired"
  def archived? = state == "archived"

  def expired_or_over_cap?
    return true if state == "expired"
    return true if expires_at.present? && Time.current >= expires_at
    return true if click_cap.present? && clicks_count >= click_cap
    false
  end

  private

  def governance_redirect(type)
    case type
    when :paused  then paused_redirect_url.presence
    when :expired then expired_redirect_url.presence
    end
  end

  def log_destination_change
    return unless governance_enabled?

    old_url = original_url_was
    new_url = original_url
    destination_histories.where(active_until: nil).update_all(active_until: Time.current)
    destination_histories.build(destination_url: new_url, active_from: Time.current)
    governance_logs.build(
      action: "destination_update",
      before_state: { destination_url: old_url },
      after_state: { destination_url: new_url },
      reason: "Direct update"
    )
  end

  def record_initial_destination
    destination_histories.create!(destination_url: original_url, active_from: created_at) if governance_enabled?
  end
end
