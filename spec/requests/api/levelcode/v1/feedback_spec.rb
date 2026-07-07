require "rails_helper"

RSpec.describe "Api::Levelcode::V1::Feedback", type: :request do
  let(:user) { create(:user) }

  before do
    allow_any_instance_of(Api::Levelcode::V1::BaseController).to receive(:authenticate_levelcode!).and_return(true)
    allow_any_instance_of(Api::Levelcode::V1::BaseController).to receive(:current_levelcode_user).and_return(user)
    allow_any_instance_of(Api::Levelcode::V1::BaseController).to receive(:current_user).and_return(user)
  end

  it "records a thumbs-up against the model" do
    expect {
      post "/api/levelcode/v1/feedback", params: { rating: "up", model: "moonshotai/kimi-k2.7-code" }, as: :json
    }.to change(UsageFeedback, :count).by(1)

    expect(response).to have_http_status(:ok)
    fb = UsageFeedback.last
    expect(fb.user_id).to eq(user.id)
    expect(fb.rating).to eq("up")
    expect(fb.model).to eq("moonshotai/kimi-k2.7-code")
  end

  it "rejects an invalid rating (422) without recording" do
    expect {
      post "/api/levelcode/v1/feedback", params: { rating: "meh", model: "x" }, as: :json
    }.not_to change(UsageFeedback, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig("error", "code")).to eq("invalid_rating")
  end
end
