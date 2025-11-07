require 'rails_helper'

RSpec.describe PublishJob, type: :job do
  let(:user) { create(:user) }
  let(:draft) { create(:brand_page, :draft, user: user) }
  let!(:published_version) do
    # Simulate the publish! call which creates a published version
    draft.publish!
    draft.reload.published_version
  end

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: 'cus_test123'))
  end

  describe '#perform' do
    let(:mock_publisher) { instance_double(GithubPagesPublisher) }

    before do
      allow(GithubPagesPublisher).to receive(:new).and_return(mock_publisher)
    end

    context 'when publishing succeeds' do
      let(:success_result) do
        {
          success: true,
          published_url: "https://#{published_version.lookup_code}.thin.ly",
          published_at: Time.current
        }
      end

      before do
        allow(mock_publisher).to receive(:publish).and_return(success_result)
      end

      it 'updates the brand page with published URL and timestamp' do
        PublishJob.new.perform(published_version.lookup_code)

        published_version.reload
        expect(published_version.published_url).to eq(success_result[:published_url])
        expect(published_version.published_at).to be_within(1.second).of(success_result[:published_at])

        # Also check that the draft version gets updated
        draft.reload
        expect(draft.published_url).to eq(success_result[:published_url])
        expect(draft.published_at).to be_within(1.second).of(success_result[:published_at])
      end

      it 'logs success message' do
        expect(Rails.logger).to receive(:info).with(/Successfully published brand page/)

        PublishJob.new.perform(published_version.lookup_code)
      end
    end

    context 'when publishing fails' do
      let(:failure_result) do
        {
          success: false,
          error: "GitHub API Error: Repository not found"
        }
      end

      before do
        allow(mock_publisher).to receive(:publish).and_return(failure_result)
      end

      it 'does not update the brand page' do
        original_url = published_version.published_url
        original_time = published_version.published_at
        original_status = published_version.status

        PublishJob.new.perform(published_version.lookup_code)

        published_version.reload
        expect(published_version.published_url).to eq(original_url)
        expect(published_version.published_at).to eq(original_time)
        expect(published_version.status).to eq(original_status) # Status not changed on failure
      end

      it 'logs error message' do
        expect(Rails.logger).to receive(:error).with(/Failed to publish brand page/)

        PublishJob.new.perform(published_version.lookup_code)
      end
    end

    context 'when brand page does not exist' do
      it 'does nothing and does not raise error' do
        expect { PublishJob.new.perform('nonexistent') }.not_to raise_error
      end
    end
  end
end
