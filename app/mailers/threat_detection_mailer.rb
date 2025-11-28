class ThreatDetectionMailer < ApplicationMailer
  def threat_found(link, detection)
    @link = link
    @detection = detection
    @user = link.user

    mail(
      to: @user.email,
      subject: "Security Alert: Threat detected in your link"
    )
  end
end
