# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  # before_action :authenticate_user_with_jwt, only: :destroy
  respond_to :json

  skip_before_action :verify_authenticity_token
  # before_action :configure_sign_in_params, only: [:create]

  # GET /resource/sign_in
  # def new
  #   super
  # end

  # POST /resource/sign_in
  # def create
  #   super
  # end

  # DELETE /resource/sign_out
  # def destroy
  #   super
  # end

  # protected

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_in_params
  #   devise_parameter_sanitizer.permit(:sign_in, keys: [:attribute])
  # end
  def respond_with(resource, _opts = {})
    render :create, status: :ok
  end

  def respond_to_on_destroy
    if request.headers["Authorization"].present?
      secret = Rails.application.credentials.fetch(:secret_key_base)
      jwt_payload = JWT.decode(request.headers["Authorization"].split(" ").last, secret).first
      current_user = User.where(id: jwt_payload["sub"]).first
    end
    if current_user
      render json: {
        status: 200,
        message: "logged out successfully"
      }, status: :ok
    else
      render json: {
        status: 401,
        message: "Couldn't find an active session."
      }, status: :unauthorized
    end
  end
end
