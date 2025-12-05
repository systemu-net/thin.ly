class QrCodeGeneratorJob
  include Sidekiq::Job
  queue_as :default

  def perform(link_id)
    link = Link.find_by(id: link_id)
    return unless link

    user = link.user
    return unless user

    # Check if QR code already exists for this link and user
    existing_qr = link.qr_codes.find_by(user_id: user.id)
    return if existing_qr

    # Generate QR code for the link
    qr_generator = QrGenerator.new(nil, link.lookup_code, user.id)
    qr_code = qr_generator.generate_qr_code

    return Rails.logger.error("Failed to generate QR code for link #{link_id}: #{qr_code.errors.full_messages.join(', ')}") if qr_code.errors.any?

    # Log API request for QR code generation
    user.plan.api_requests.create(logable: qr_code)
    Rails.logger.info("Successfully generated QR code for link #{link_id}")
  rescue StandardError => e
    Rails.logger.error("QrCodeGeneratorJob failed for link #{link_id}: #{e.message}")
    raise e
  end
end
