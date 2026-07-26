module Api
  module Levelcode
    module V1
      # Admin-only dashboard API. Gated on the user's `admin?` role (assigned from the Rails
      # console: `user.update!(role: "admin")`). Authenticates like the rest of the namespace
      # (editor bearer OR web session), then requires admin on top.
      class AdminController < BaseController
        before_action :require_admin!

        # GET /api/levelcode/v1/admin/summary
        def summary
          render json: ::Levelcode::AdminReport.summary, status: :ok
        end

        # GET /api/levelcode/v1/admin/users?sort=&dir=&q=&plan=&limit=&offset=
        def users
          render json: ::Levelcode::AdminReport.users(
            sort: params[:sort].presence || "input",
            dir: params[:dir].presence || "desc",
            q: params[:q].presence,
            plan: params[:plan].presence,
            limit: params.fetch(:limit, 100).to_i.clamp(1, 500),
            offset: params[:offset].to_i.clamp(0, 1_000_000)
          ), status: :ok
        end

        # GET /api/levelcode/v1/admin/referrals?from=YYYY-MM-DD&to=YYYY-MM-DD
        # Referral funnel per marketing channel: clicks -> signups -> paid.
        def referrals
          render json: ::Levelcode::ReferralReport.funnel(
            from: params[:from].presence,
            to: params[:to].presence
          ), status: :ok
        rescue Date::Error
          render_levelcode_error("bad_request", "from/to must be YYYY-MM-DD dates", :bad_request)
        end

        private

        def require_admin!
          return if current_levelcode_user&.admin?

          render_levelcode_error("forbidden", "Admin access required", :forbidden)
        end
      end
    end
  end
end
