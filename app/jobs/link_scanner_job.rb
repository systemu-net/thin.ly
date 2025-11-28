class LinkScannerJob
  include Sidekiq::Job

  sidekiq_options queue: "safe_browsing", retry: 3

  def perform(link_id)
    link = Link.find_by(id: link_id)
    return unless link

    result = safe_browsing_service.check_url(link.original_url)

    link.update!(
      is_safe: result[:safe],
      last_scanned_at: Time.current,
      scan_failures: 0
    )

    if !result[:safe]
      # Create threat detection record
      detection = link.threat_detections.create!(
        url: link.original_url,
        threat_types: result[:threat_types],
        platform_types: result[:platform_types],
        severity: result[:severity],
        status: "active"
      )

      # Send notification email
      ThreatDetectionMailer.threat_found(link, detection).deliver_later

      # Optionally deactivate the link
      link.update!(active: false) if link.respond_to?(:active=)
    end

  rescue => e
    Rails.logger.error("Link scanner job failed for link #{link_id}: #{e.message}")
    link&.increment!(:scan_failures)
    raise # Let Sidekiq handle retry
  end

  private

  def safe_browsing_service
    @safe_browsing_service ||= SafeBrowsingService.new
  end
end
