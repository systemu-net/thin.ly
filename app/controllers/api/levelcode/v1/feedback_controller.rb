module Api
  module Levelcode
    module V1
      # POST /api/levelcode/v1/feedback — record a thumbs up/down the editor sends when a
      # user reacts to an assistant turn on the metered gateway. Bearer-authed; BYOK
      # never reaches here (it stays local + private). Keeps the per-user RPM cap
      # (enforce_abuse_caps!) so a client can't loop unbounded INSERTs into the table.
      class FeedbackController < BaseController
        def create
          rating = params[:rating].to_s
          unless UsageFeedback::RATINGS.include?(rating)
            return render_levelcode_error("invalid_rating", "rating must be 'up' or 'down'", :unprocessable_content)
          end

          UsageFeedback.create!(
            user: current_levelcode_user,
            model: params[:model].to_s.presence,
            rating: rating,
            request_id: params[:request_id].to_s.presence,
            created_at: Time.current
          )
          render json: { ok: true }, status: :ok
        end
      end
    end
  end
end
