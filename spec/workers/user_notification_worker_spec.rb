# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserNotificationWorker, type: :worker do
  describe '#perform' do
    let(:user) { create(:user) }
    let(:mailer_double) { double('UserMailer') }

    it 'sends notification email to the user' do
      expect(UserMailer).to receive(:created).with(user).and_return(mailer_double)
      expect(mailer_double).to receive(:deliver_now)

      described_class.new.perform(user.id)
    end

    it 'raises error if user not found' do
      expect {
        described_class.new.perform(999999)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'sidekiq options' do
    it 'uses mailers queue' do
      expect(described_class.sidekiq_options['queue']).to eq(:mailers)
    end

    it 'retries 3 times' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end
end
