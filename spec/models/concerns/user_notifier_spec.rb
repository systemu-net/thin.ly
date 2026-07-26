# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserNotifier, type: :concern do
  describe 'callbacks' do
    it 'enqueues UserNotificationWorker after the create COMMITS' do
      # after_commit, not after_create: enqueueing inside the transaction lets
      # Sidekiq pick the job up before the row is visible, which fails User.find
      # and burns a retry.
      expect(UserNotificationWorker).to receive(:perform_in).with(UserNotifier::NOTIFY_DELAY, kind_of(Integer))
      create(:user)
    end

    it 'delays the send so OAuth attribution is stamped before the email renders' do
      # Levelcode::WebController#stamp_oauth_attribution! writes the channel just
      # after the user row is created (GitHub and Google build the user through
      # two different services, so it cannot be passed into the create). Sending
      # immediately would race that write and report every OAuth signup as organic.
      expect(UserNotifier::NOTIFY_DELAY).to be >= 30.seconds
    end
  end

  describe '#send_created_email' do
    it 'enqueues worker with user id' do
      existing_user = create(:user)
      expect(UserNotificationWorker).to receive(:perform_in).with(UserNotifier::NOTIFY_DELAY, existing_user.id)
      existing_user.send(:send_created_email)
    end
  end
end
