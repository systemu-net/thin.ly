# frozen_string_literal: true

# Fires the internal "new signup" notification (UserMailer#created).
module UserNotifier
  extend ActiveSupport::Concern

  # How long to wait before sending. Two reasons, both about the email being RIGHT
  # rather than instant:
  #
  #   * OAuth signups get their marketing attribution stamped just AFTER the user
  #     row is created (Levelcode::WebController#stamp_oauth_attribution!), because
  #     GitHub and Google build the user through two different services. Sending
  #     immediately would race that write and report every OAuth signup as
  #     "Organic".
  #   * It keeps the job off the enqueue-before-commit knife edge entirely.
  #
  # This is an ops notification, so a minute of latency costs nothing.
  NOTIFY_DELAY = 1.minute

  included do
    # after_commit, not after_create: perform_async inside the transaction can be
    # picked up by Sidekiq before the row is visible, and the job then fails its
    # User.find and burns a retry.
    after_commit :send_created_email, on: :create
  end

  def send_created_email
    UserNotificationWorker.perform_in(NOTIFY_DELAY, id)
  end
end
