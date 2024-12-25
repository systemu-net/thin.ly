require 'rails_helper'
require 'carrierwave/test/matchers'

describe QrCodeUploader do
  include CarrierWave::Test::Matchers

  # let(:user) { create(:user) }
  # let(:link) { create(:link, user: user) }
  # let(:uploader) { described_class.new(user, :qr_code) }

  before do
    described_class.enable_processing = false
    File.open('spec/fixtures/files/qr_code.png') { |f| uploader.store!(f) }
  end

  xit 'do work' do
  end
end
