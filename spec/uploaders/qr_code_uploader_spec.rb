require 'rails_helper'
require 'carrierwave/test/matchers'

describe QrCodeUploader do
  include CarrierWave::Test::Matchers

  let(:user) { create(:user) }
  let(:link) { create(:link, user: user) }
  let(:qr_code) { build(:qr_code, user: user, link: link) }
  let(:uploader) { described_class.new(qr_code, :image) }

  before do
    described_class.enable_processing = false
  end

  after do
    described_class.enable_processing = true
    uploader.remove!
  end

  describe '#store_dir' do
    it 'returns the correct upload directory' do
      expect(uploader.store_dir).to eq('uploads/qr_code')
    end
  end

  describe 'file storage' do
    it 'stores a file' do
      File.open(Rails.root.join('spec/fixtures/files/test_avatar.jpg')) do |f|
        uploader.store!(f)
      end

      expect(uploader.file).to be_present
    end

    it 'preserves the file after store' do
      File.open(Rails.root.join('spec/fixtures/files/test_avatar.jpg')) do |f|
        uploader.store!(f)
      end

      expect(uploader.file.exists?).to be true
    end
  end

  describe 'mounted on QrCode model' do
    it 'accepts an image upload via the model' do
      qr_code.image = Rack::Test::UploadedFile.new(
        Rails.root.join('spec/fixtures/files/test_avatar.jpg'), 'image/jpeg'
      )
      qr_code.save(validate: false)

      expect(qr_code.image).to be_present
      expect(qr_code.image.url).to include('uploads/qr_code')
    end
  end
end
