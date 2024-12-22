class QrCodesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_qr_code, only: %i[destroy]

  def create
    @qr_code = current_user.qr_codes.create(qr_code_params)

    if @qr_code.errors.any?
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

  def qr_code_params
    params.require(:qr_code).permit(:link_id)
  end

  def set_qr_code
    @qr_code = current_user.qr_codes.find_by_id(params[:id])

    render json: { error: "Qr Code is not found" }, status: :not_found unless @qr_code
  end
end
