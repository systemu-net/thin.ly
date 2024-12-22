module Api
  module V1
    class LinksController < ApplicationController
      before_action :authenticate_user!, only: %i[index show create update destroy]
      skip_before_action :verify_authenticity_token, only: [ :create, :update ]
      before_action :set_link, only: %i[lookup_code show update destroy]

      def index
        @links = current_user.links.includes(:qr_codes)
          .order(created_at: :desc)

        render :index, status: :ok
      end

      def lookup_code
        if @link
          redirect_to @link.original_url, allow_other_host: true
        else
          render json: { error: "Link not found" }, status: :not_found
        end
      end

      def show
        if @link
          @qr_codes = @link.qr_codes.includes(:user)
          render :show, status: :ok
        else
          render json: { error: "Link not found" }, status: :not_found
        end
      end

      def create
        shortener = Shortener.new(link_params[:original_url], current_user.id)
        @link = shortener.generate_short_link

        if @link.errors.any?
          return render json: { errors: @link.errors.full_messages }, status: :unprocessable_entity
        end

        render :create, status: :created
      end

      def update
        # request_body = JSON.parse(request.body.read)
        # Rails.logger.info "Request Body: #{request_body.inspect}"
        if current_user.id != @link.user_id
          return render json: { error: "Unauthorized" }, status: :unauthorized
        end

        if @link.update(link_params)
          render :update, status: :ok
        else
          render json: { errors: @link.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        if current_user.id != @link.user_id
          render json: { error: "Unauthorized" }, status: :unauthorized
        end

        if @link.destroy
          render json: {}, status: :no_content
        else
          render json: { errors: @link.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def link_params
        params.require(:link).permit(
          :original_url, :lookup_code
        )
      end

      def set_link
        @link = Link.find_by_lookup_code(params[:lookup_code])

        render json: { error: "Link not found" }, status: :not_found unless @link
      end
    end
  end
end
