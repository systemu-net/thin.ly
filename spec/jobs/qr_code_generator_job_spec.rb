require 'rails_helper'

RSpec.describe QrCodeGeneratorJob, type: :job do
  let(:user) { create(:user) }
  let(:link) { create(:link, user: user) }

  describe '#perform' do
    context 'when link exists' do
      context 'and no QR code exists for the user' do
        it 'generates a QR code for the link' do
          expect {
            QrCodeGeneratorJob.new.perform(link.id)
          }.to change { link.qr_codes.count }.by(1)
        end

        it 'creates QR code for the correct user' do
          QrCodeGeneratorJob.new.perform(link.id)
          qr_code = link.qr_codes.last
          expect(qr_code.user_id).to eq(user.id)
        end

        it 'creates QR code with valid image' do
          QrCodeGeneratorJob.new.perform(link.id)
          qr_code = link.qr_codes.last
          expect(qr_code.image).to be_present
        end

        it 'logs API request for QR code generation' do
          expect {
            QrCodeGeneratorJob.new.perform(link.id)
          }.to change { user.plan.api_requests.where(logable_type: 'QrCode').count }.by(1)
        end

        it 'creates API request with correct logable' do
          QrCodeGeneratorJob.new.perform(link.id)
          qr_code = link.qr_codes.last
          api_request = user.plan.api_requests.where(logable: qr_code).last
          expect(api_request).to be_present
          expect(api_request.logable_type).to eq('QrCode')
          expect(api_request.logable_id).to eq(qr_code.id)
        end
      end

      context 'when QR code already exists' do
        before do
          create(:qr_code, link: link, user: user)
        end

        it 'does not create duplicate QR code' do
          expect {
            QrCodeGeneratorJob.new.perform(link.id)
          }.not_to change { link.qr_codes.count }
        end
      end
    end

    context 'when link does not exist' do
      it 'does not raise an error' do
        expect {
          QrCodeGeneratorJob.new.perform(999999)
        }.not_to raise_error
      end

      it 'does not create any QR codes' do
        expect {
          QrCodeGeneratorJob.new.perform(999999)
        }.not_to change { QrCode.count }
      end
    end
  end
end
