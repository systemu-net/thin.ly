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
        ActiveRecord::Base.transaction do
          if @brand_page.published?
            # If deleting a published version, also delete its draft
            @brand_page.draft_version&.destroy
          elsif @brand_page.draft? && @brand_page.published_version&.published?
            # If deleting a draft that has a published version, unpublish first
            @brand_page.published_version.unpublish!
          end

          @brand_page.destroy
        end

        head :no_content
      end

      def publish
        @published_version = @brand_page.publish!
        @brand_page = @published_version
        render :show, status: :ok
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end

      def unpublish
        draft_version = @brand_page.draft_version
        @brand_page.unpublish!
        # Return the draft version for the response
        @brand_page = draft_version
        render :show, status: :ok
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
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
