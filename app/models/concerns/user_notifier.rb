module UserNotifier
  extend ActiveSupport::Concern

  included do
    after_create :send_created_email
  end

  def send_created_email
    UserMailer.created(self).deliver_later
  end
end
