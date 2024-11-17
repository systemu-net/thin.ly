module Api
  module V1
    class LinksController < ApplicationController
      skip_before_action :verify_authenticity_token, only: [ :create, :update ]
      before_action :set_link, only: %i[show update]
      def index
        links = Link.all

        render json: links
      end

      def show
        if @link
          redirect_to @link.original_url, allow_other_host: true
        else
          render json: { error: "Link not found" }, status: :not_found
        end
      end

      def create
        shortener = Shortener.new(link_params[:original_url])
        @link = shortener.generate_short_link

        if @link.errors.any?
          return render json: { errors: @link.errors.full_messages }, status: :unprocessable_entity
        end

        render :create, status: :created
      end

      def update
        byebug
        if @link.update(params[:original_url])
          byebug
          render json: @link
        else
          byebug
          render json: { errors: link.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def link_params
        params.require(:link).permit(
          :original_url
        )
      end

      def set_link
        @link = Link.find_by_lookup_code(params[:lookup_code])
      end
    end
  end
end
