# frozen_string_literal: true

class UserNotificationWorker
  include Sidekiq::Worker

  sidekiq_options queue: :mailers, retry: 3

  def perform(user_id)
    user = User.find(user_id)
    UserMailer.created(user).deliver_now
  end
end
