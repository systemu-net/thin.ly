module Api
  module V1
    class QrCodesController < ApplicationController
      before_action :authenticate_user!, only: %i[index create destroy]
      skip_before_action :verify_authenticity_token, only: [ :create ]
      before_action :set_qr_code, only: %i[destroy]

      def index
        @qr_codes = current_user.qr_codes
          .order(created_at: :desc)

        render :index, status: :ok
      end

      def create
        existing_qr_code.destroy if existing_qr_code
        @qr_code = QrGenerator.new(
          qr_codes_params[:original_url],
          qr_codes_params[:lookup_code],
          current_user.id
        ).generate_qr_code

        if @qr_code.errors.full_messages.any?
          return render json: { errors: @qr_code.errors.full_messages }, status: :unprocessable_entity
        end

        render :create, status: :created
      end

      def destroy
        if @qr_code.destroy
          render json: {}, status: :no_content
        else
          render json: { errors: @qr_code.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def qr_codes_params
        params.require(:qr_code).permit(
          :original_url, :lookup_code
        )
      end

      def existing_qr_code
        @existing_qr_code =
          QrCode.joins(:link).where(user_id: current_user.id, links: { lookup_code: qr_codes_params[:lookup_code] }).first
      end

      def set_qr_code
        @qr_code = current_user.qr_codes.find_by_id(params[:id])

        render json: { error: "Qr Code is not found" }, status: :not_found unless @qr_code
      end
    end
  end
end
