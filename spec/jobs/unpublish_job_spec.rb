require 'rails_helper'

RSpec.describe UnpublishJob, type: :job do
  let(:user) { create(:user) }
  let(:brand_page) { create(:brand_page, :published, user: user) }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test123'))
  end

  describe '#perform' do
    let(:mock_publisher) { instance_double(GithubPagesPublisher) }

    before do
      allow(GithubPagesPublisher).to receive(:new).and_return(mock_publisher)
    end

    context 'when unpublishing succeeds' do
      let(:success_result) { { success: true } }

      before do
        allow(mock_publisher).to receive(:unpublish).and_return(success_result)
      end

      it 'deletes the brand page' do
        brand_page_id = brand_page.id

        UnpublishJob.new.perform(brand_page.lookup_code)

        expect(BrandPage.find_by(id: brand_page_id)).to be_nil
      end

      it 'logs success message' do
        allow(Rails.logger).to receive(:info)
        expect(Rails.logger).to receive(:info).with(match(/Successfully unpublished and deleted brand page/))

        UnpublishJob.new.perform(brand_page.lookup_code)
      end
    end

    context 'when unpublishing fails' do
      let(:failure_result) do
        {
          success: false,
          error: "GitHub API Error: File not found"
        }
      end

      before do
        allow(mock_publisher).to receive(:unpublish).and_return(failure_result)
      end

      it 'does not delete the brand page' do
        brand_page_id = brand_page.id

        UnpublishJob.new.perform(brand_page.lookup_code)

        expect(BrandPage.find_by(id: brand_page_id)).to be_present
      end

      it 'logs error message' do
        expect(Rails.logger).to receive(:error).with(/Failed to unpublish brand page/)

        UnpublishJob.new.perform(brand_page.lookup_code)
      end
    end

    context 'when brand page does not exist' do
      it 'does nothing and does not raise error' do
        expect { UnpublishJob.new.perform('nonexistent') }.not_to raise_error
      end
    end
  end
end
