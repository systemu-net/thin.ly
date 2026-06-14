module Api
  module V1
    # Issues presigned S3 URLs so the browser can upload images directly to S3.
    class UploadsController < ApplicationController
      before_action :authenticate_user!
      skip_before_action :verify_authenticity_token

      # POST /api/v1/uploads/presign  { content_type: "image/png" }
      def presign
        unless S3Uploads.configured?
          return render json: { error: "Image storage is not configured" }, status: :service_unavailable
        end

        data = S3Uploads.presign(content_type: params[:content_type], user_id: current_user.id)
        render json: data, status: :ok
      rescue ArgumentError => e
        render json: { error: e.message }, status: :unprocessable_content
      rescue Aws::Errors::ServiceError => e
        Rails.logger.error("Presign error: #{e.class}: #{e.message}")
        render json: { error: "Could not prepare the upload." }, status: :bad_gateway
      end
    end
  end
end
