module Api
  module V1
    # Public, by-handle profile read endpoint (thin.ly/@handle). No auth is
    # required, but current_user is read opportunistically to set is_owner and
    # to let an owner "view as visitor". Privacy is enforced HERE, server-side.
    class PublicProfilesController < ApplicationController
      skip_before_action :verify_authenticity_token

      # GET /api/v1/profiles/:handle
      def show
        @profile = Profile.find_by_handle(params[:handle])
        return render json: { error: "Profile not found" }, status: :not_found unless @profile

        @is_owner = current_user.present? && current_user.id == @profile.user_id

        # Private profiles return only a placeholder payload — never the bio,
        # links or socials — even to the owner on this (visitor-facing) endpoint.
        @private = !@profile.is_public?

        unless @private
          @profile_links = @profile.public_profile_links
          @spark = LinkClickSeriesService.call(@profile_links.map(&:link_id), days: 7)
        end

        render :show, status: :ok
      end

      # GET /api/v1/profiles/:handle/qr
      # A scannable QR (SVG) for the profile URL — "scan to connect". Served as
      # an image so it can be used directly in an <img>. Public profiles only.
      def qr
        require "rqrcode"
        profile = Profile.find_by_handle(params[:handle])
        return head :not_found unless profile&.is_public?

        svg = RQRCode::QRCode.new(profile.public_url, level: :m).as_svg(
          color: "15151b",
          shape_rendering: "crispEdges",
          module_size: 5,
          standalone: true,
          use_path: true,
          viewbox: true
        )

        expires_in 1.hour, public: true
        render body: svg, content_type: "image/svg+xml"
      end
    end
  end
end
