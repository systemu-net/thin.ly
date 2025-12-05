module Api
  module V1
    class LinksController < ApplicationController
      before_action :authenticate_user!, only: %i[index search show create update destroy]
      skip_before_action :verify_authenticity_token
      before_action :set_link, only: %i[show update destroy]
      before_action :set_link_for_lookup, only: %i[lookup_code]
      before_action :check_link_authorization, only: %i[show update destroy]
      before_action :check_api_limit, only: %i[create]

      def index
        @links = current_user.links.includes(:qr_codes)
          .order(created_at: :desc)

        render :index, status: :ok
      end

      def search
        query = params[:query]

        if query.blank?
          return render json: { error: "Query parameter is required" }, status: :bad_request
        end

        @links = current_user.links
          .where("original_url ILIKE ? OR title ILIKE ?", "%#{query}%", "%#{query}%")
          .order(created_at: :desc)

        render :index, status: :ok
      end

      def lookup_code
        if @link
          # Block unsafe links and show warning page
          if @link.is_safe == false
            return redirect_to unsafe_link_path
          end

          Rails.logger.debug("Redirecting to: #{@link.original_url}")
          log_click(@link)
          redirect_to @link.original_url, allow_other_host: true
        else
          redirect_to link_not_found_path
        end
      end

      def show
        if @link
          @qr_codes = @link.qr_codes.includes(:user)
          @clicks = @link.clicks
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

        scan_link(@link)
        generate_qr_code(@link)
        log_api_request(@link)
        render :create, status: :created
      end

      def update
        @link.update(link_params)

        if @link.errors.any?
          return render json: { errors: @link.errors.full_messages }, status: :unprocessable_entity
        end

        scan_link(@link)
        render :update, status: :ok
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

      def check_link_authorization
        if current_user.id != @link.user_id
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      end

      def link_params
        params.require(:link).permit(:original_url, :title, :description)
      end

      def log_click(link)
        # Capture the 'r' parameter to track source (e.g., ?r=qr for QR code scans)
        source = params[:r]
        ClickJob.new.perform(link.lookup_code, request.remote_ip, request.user_agent, request.referrer, source)
      end

      def scan_link(link)
        LinkScannerJob.perform_async(link.id)
      end

      def generate_qr_code(link)
        QrCodeGeneratorJob.perform_async(link.id)
      end

      def set_link
        @link = Link.find_by(lookup_code: params[:lookup_code])

        render json: { error: "Link not found" }, status: :not_found unless @link
      end

      def set_link_for_lookup
        @link = Link.find_by(lookup_code: params[:lookup_code])
        # Don't render anything here - let lookup_code action handle the response
      end
    end
  end
end
