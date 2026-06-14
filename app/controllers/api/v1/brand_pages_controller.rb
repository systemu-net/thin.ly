module Api
  module V1
    class BrandPagesController < ApplicationController
      before_action :authenticate_user!
      skip_before_action :verify_authenticity_token
      before_action :set_brand_page, only: %i[show update destroy publish unpublish]
      before_action :check_owner!, only: %i[show update destroy publish unpublish]
      before_action :check_api_limit, only: %i[create]

      def index
        @brand_pages = current_user.brand_pages.drafts.order(updated_at: :desc)
        render :index, status: :ok
      end

      # POST /api/v1/brand_pages/preview
      # Renders template HTML from arbitrary content WITHOUT persisting — used by
      # the editor/wizard to show a live iframe preview of the portfolio template.
      def preview
        content = (params[:content].respond_to?(:to_unsafe_h) ? params[:content].to_unsafe_h : params[:content]) || {}
        content = content.deep_stringify_keys
        page = OpenStruct.new(
          title: params[:title].to_s,
          description: params[:description].to_s,
          content: content,
          lookup_code: "preview"
        )

        html =
          if content["template"] == "portfolio"
            ApplicationController.render(template: "link_in_bio/portfolio", layout: false, assigns: { page: page, user: current_user })
          else
            ApplicationController.render(template: "link_in_bio/static", layout: "link_in_bio_public",
              assigns: { page: page, user: current_user, links: [], tracking_enabled: false })
          end

        render json: { html: html }, status: :ok
      end

      # POST /api/v1/brand_pages/generate
      # Generates (but does not persist) a page design from an AI prompt.
      def generate
        images = Array(params[:images]).map { |i| { "key" => i[:key], "url" => i[:url] } }
        spec = PageGeneratorService.new(
          prompt: params[:prompt],
          name: params[:name],
          images: images,
          template: params[:template]
        ).call
        render json: { page: spec }, status: :ok
      rescue PageGeneratorService::GenerationError => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      def show
        render :show, status: :ok
      end

      def create
        @brand_page = current_user.brand_pages.new(brand_page_params)

        @brand_page.save

        if @brand_page.errors.full_messages.any?
          return render json: { errors: @brand_page.errors.full_messages }, status: :unprocessable_content
        end

        log_api_request(@brand_page)
        render :show, status: :created
      end

      def update
        if @brand_page.published?
          render json: { error: "Cannot update a published brand page. Please create a draft version first." },
                 status: :unprocessable_content and return
        end

        if @brand_page.update(brand_page_params)
          render :show, status: :ok
        else
          render json: { errors: @brand_page.errors.full_messages }, status: :unprocessable_content
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
        render json: { error: e.message }, status: :unprocessable_content
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
      end

      def unpublish
        draft_version = @brand_page.draft_version
        @brand_page.unpublish!
        # Return the draft version for the response
        @brand_page = draft_version
        render :show, status: :ok
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      private

      def brand_page_params
        params.require(:brand_page).permit(:title, :description, content: {})
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
