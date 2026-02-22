module Api
  module V1
    class UsersController < ApplicationController
      before_action :authenticate_user!
      skip_before_action :verify_authenticity_token

      # GET /api/v1/user
      def show
        @user = current_user
        render :show, status: :ok
      end

      # PATCH /api/v1/user
      def update
        @user = current_user
        if @user.update(user_params)
          render :show, status: :ok
        else
          render json: { errors: @user.errors.full_messages }, status: :unprocessable_content
        end
      end

      # PATCH /api/v1/user/avatar
      def update_avatar
        avatar_param = params[:avatar]

        if avatar_param.present?
          current_user.avatar = avatar_param

          if current_user.save
            render json: {
              message: "Avatar uploaded successfully",
              avatar_url: current_user.avatar.url
            }, status: :ok
          else
            render json: { errors: current_user.errors.full_messages }, status: :unprocessable_content
          end
        else
          render json: { error: "No avatar file provided" }, status: :unprocessable_content
        end
      rescue ActionController::BadRequest => e
        render json: { error: "Invalid file upload: #{e.message}" }, status: :bad_request
      end

      # DELETE /api/v1/user/avatar
      def destroy_avatar
        if current_user.avatar.present?
          current_user.remove_avatar!
          current_user.save
          render json: { message: "Avatar removed successfully" }, status: :ok
        else
          render json: { error: "No avatar to remove" }, status: :unprocessable_content
        end
      end

      private

      def user_params
        params.require(:user).permit(:avatar)
      end
    end
  end
end
