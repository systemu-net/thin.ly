module Api
  module V1
    class LinksController < ApplicationController
      before_action :authenticate_user!, only: %i[index search show create update destroy analytics]
      skip_before_action :verify_authenticity_token
      before_action :set_link, only: %i[show update destroy analytics]
      before_action :set_link_for_lookup, only: %i[lookup_code]
      before_action :check_link_authorization, only: %i[show update destroy analytics]
      before_action :check_api_limit, only: %i[create]

      def index
        @links = current_user.links.includes(:qr_codes)

        # Apply sorting based on params
        @links = apply_sorting(@links, params[:sort], params[:order])

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

      def analytics
        # Date range filtering
        start_date = params[:start_date] ? Date.parse(params[:start_date]) : 30.days.ago
        end_date = params[:end_date] ? Date.parse(params[:end_date]) : Date.today

        # Base query for the date range
        clicks_in_range = @link.clicks.where(created_at: start_date.beginning_of_day..end_date.end_of_day)

        # Summary statistics
        @total_clicks = clicks_in_range.count
        @human_clicks = clicks_in_range.human_traffic.count
        @bot_clicks = clicks_in_range.bots.count
        @qr_scans = clicks_in_range.qr_scans.count
        @direct_clicks = clicks_in_range.direct_clicks.count

        # Device breakdown
        @device_stats = {
          mobile: clicks_in_range.mobile.count,
          desktop: clicks_in_range.desktop.count,
          tablet: clicks_in_range.tablet.count
        }

        # Top locations (city level)
        @top_cities = clicks_in_range.human_traffic
          .where.not(city: nil)
          .group(:city, :region, :country_name)
          .count
          .sort_by { |_k, v| -v }
          .first(10)
          .map { |(city, region, country), count| { city: city, region: region, country: country, clicks: count } }

        # Country breakdown
        @countries = clicks_in_range.human_traffic
          .where.not(country_name: nil)
          .group(:country_name)
          .count
          .sort_by { |_k, v| -v }
          .map { |country, count| { country: country, clicks: count } }

        # Browser breakdown
        @browsers = clicks_in_range.human_traffic
          .where.not(browser: nil)
          .group(:browser)
          .count
          .sort_by { |_k, v| -v }
          .map { |browser, count| { browser: browser, clicks: count } }

        # Operating system breakdown
        @operating_systems = clicks_in_range.human_traffic
          .where.not(os: nil)
          .group(:os)
          .count
          .sort_by { |_k, v| -v }
          .map { |os, count| { os: os, clicks: count } }

        # Time series data (daily clicks)
        @daily_clicks = clicks_in_range
          .group("DATE(created_at)")
          .count
          .map { |date, count| { date: date.to_s, clicks: count } }
          .sort_by { |d| d[:date] }

        # Recent clicks with full details (last 20)
        @recent_clicks = clicks_in_range
          .order(created_at: :desc)
          .limit(20)
          .select(:id, :city, :region, :country_name, :device_type, :browser, :os, :is_bot, :source, :created_at)

        render :analytics, status: :ok
      end

      private

      def check_link_authorization
        if current_user.id != @link.user_id
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      end

      def apply_sorting(scope, sort_by, order)
        sort_by ||= "created_at"
        order ||= "desc"

        case sort_by
        when "created_at"
          order == "asc" ? scope.by_created_asc : scope.by_created_desc
        when "clicks", "clicks_count"
          order == "asc" ? scope.by_clicks_asc : scope.by_clicks_desc
        when "last_clicked"
          order == "asc" ? scope.by_last_clicked_asc : scope.by_last_clicked_desc
        else
          scope.by_created_desc # default
        end
      end

      def link_params
        params.require(:link).permit(:original_url, :title, :description)
      end

      def log_click(link)
        # Capture the 'r' parameter to track source (e.g., ?r=qr for QR code scans)
        source = params[:r]

        # Extract CloudFront headers for geolocation and device detection
        cloudfront_headers = extract_cloudfront_headers

        ClickJob.perform_async(
          link.lookup_code,
          request.remote_ip,
          request.user_agent,
          request.referrer,
          source,
          cloudfront_headers
        )
      end

      def extract_cloudfront_headers
        {
          # Geolocation data
          "country" => request.headers["CloudFront-Viewer-Country"],
          "country_name" => request.headers["CloudFront-Viewer-Country-Name"],
          "city" => request.headers["CloudFront-Viewer-City"],
          "region" => request.headers["CloudFront-Viewer-Country-Region-Name"],
          "postal_code" => request.headers["CloudFront-Viewer-Postal-Code"],
          "latitude" => request.headers["CloudFront-Viewer-Latitude"],
          "longitude" => request.headers["CloudFront-Viewer-Longitude"],
          "timezone" => request.headers["CloudFront-Viewer-Time-Zone"],

          # Device type detection
          "is_mobile" => request.headers["CloudFront-Is-Mobile-Viewer"] == "true",
          "is_tablet" => request.headers["CloudFront-Is-Tablet-Viewer"] == "true",
          "is_desktop" => request.headers["CloudFront-Is-Desktop-Viewer"] == "true",
          "is_android" => request.headers["CloudFront-Is-Android-Viewer"] == "true",
          "is_ios" => request.headers["CloudFront-Is-IOS-Viewer"] == "true",
          "is_smarttv" => request.headers["CloudFront-Is-SmartTV-Viewer"] == "true"
        }
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
