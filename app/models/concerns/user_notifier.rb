module UserNotifier
  extend ActiveSupport::Concern

  included do
    after_create :send_created_email
  end

  def send_created_email
    UserNotificationWorker.perform_async(id)
  end
end
