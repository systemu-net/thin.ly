# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserNotifier, type: :concern do
  describe 'callbacks' do
    it 'enqueues UserNotificationWorker after user creation' do
      expect(UserNotificationWorker).to receive(:perform_async).with(kind_of(Integer))
      create(:user)
    end
  end

  describe '#send_created_email' do
    it 'enqueues worker with user id' do
      existing_user = create(:user)
      expect(UserNotificationWorker).to receive(:perform_async).with(existing_user.id)
      existing_user.send(:send_created_email)
    end
  end
end
