module Api
  module V1
    class BrandPagesController < ApplicationController
      before_action :authenticate_user!
      skip_before_action :verify_authenticity_token
      before_action :set_brand_page, only: %i[show update destroy publish unpublish]
      before_action :check_owner!, only: %i[show update destroy publish unpublish]

      def index
        @brand_pages = current_user.brand_pages.order(updated_at: :desc)
        render :index, status: :ok
      end

      def show
        render :show, status: :ok
      end

      def create
        @brand_page = current_user.brand_pages.new(brand_page_params)

        if @brand_page.save
          render :show, status: :created
        else
          render json: { errors: @brand_page.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @brand_page.update(brand_page_params)
          render :show, status: :ok
        else
          render json: { errors: @brand_page.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        if @brand_page.published_at.present?
          # Unpublish and keep current draft
          @brand_page.unpublish!
        end

        @brand_page.destroy
        head :no_content
      end

      def publish
        ActiveRecord::Base.transaction do
          # Make sure only one published version exists per draft chain
          if (current_published = @brand_page.draft_source)
            current_published.unpublish!
          end

          @brand_page.publish!
        end

        render :show, status: :ok
      end

      def unpublish
        @brand_page.unpublish!
        render :show, status: :ok
      end

      private

      def brand_page_params
        params.require(:brand_page).permit(content: {})
      end

      def set_brand_page
        @brand_page = BrandPage.find_by(lookup_code: params[:lookup_code])

        render json: { error: "Brand page not found" }, status: :not_found unless @brand_page
      end

      def check_owner!
        render json: { error: "Unauthorized" }, status: :unauthorized unless @brand_page.user_id == current_user.id
      end
    end
  end
end
