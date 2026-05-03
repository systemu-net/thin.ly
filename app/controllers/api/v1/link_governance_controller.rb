module Api
  module V1
    class LinkGovernanceController < ApplicationController
      before_action :authenticate_user!
      skip_before_action :verify_authenticity_token
      before_action :set_link, only: %i[transition destination audit_log destination_history]
      before_action :authorize_link!, only: %i[transition destination audit_log destination_history]

      # POST /api/v1/links/governance/pause_all
      def pause_all
        paused_lookup_codes = []

        current_user.links
          .where(governance_enabled: true, state: "active")
          .find_each do |link|
            link.transition_to!(
              "paused",
              user: current_user,
              reason: params[:reason].presence || "Bulk pause from Governance dashboard",
              ip_address: request.remote_ip
            )
            paused_lookup_codes << link.lookup_code
          end

        render json: {
          paused_count: paused_lookup_codes.size,
          paused_lookup_codes: paused_lookup_codes,
          message: "Paused #{paused_lookup_codes.size} governed links"
        }, status: :ok
      rescue ArgumentError, ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      # PATCH /api/v1/links/:link_lookup_code/governance/transition
      def transition
        new_state = params.require(:state)

        @link.transition_to!(
          new_state,
          user: current_user,
          reason: params[:reason],
          ip_address: request.remote_ip
        )

        render json: { state: @link.state, message: "Link transitioned to #{new_state}" }, status: :ok
      rescue ArgumentError => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      # PATCH /api/v1/links/:link_lookup_code/governance/destination
      def destination
        new_url = params.require(:destination_url)

        @link.update_destination!(
          new_url,
          user: current_user,
          reason: params[:reason],
          ip_address: request.remote_ip
        )

        render json: { original_url: @link.original_url, message: "Destination updated" }, status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      # GET /api/v1/links/:link_lookup_code/governance/audit_log
      def audit_log
        @logs = @link.governance_logs
          .includes(:user)
          .order(created_at: :desc)
          .page(params[:page])

        render json: {
          logs: @logs.map { |log|
            {
              id: log.id,
              action: log.action,
              before_state: log.before_state,
              after_state: log.after_state,
              reason: log.reason,
              ip_address: log.ip_address,
              user: log.user&.email,
              created_at: log.created_at
            }
          },
          meta: pagination_meta(@logs)
        }
      rescue NameError
        # Kaminari not available — return unpaginated
        logs = @link.governance_logs.includes(:user).order(created_at: :desc).limit(100)
        render json: { logs: logs.map { |log| serialize_log(log) } }
      end

      # GET /api/v1/links/:link_lookup_code/governance/destination_history
      def destination_history
        histories = @link.destination_histories.chronological

        render json: {
          histories: histories.map { |h|
            {
              id: h.id,
              destination_url: h.destination_url,
              active_from: h.active_from,
              active_until: h.active_until
            }
          }
        }
      end

      private

      def set_link
        @link = Link.find_by!(lookup_code: params[:lookup_code])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Link not found" }, status: :not_found
      end

      def authorize_link!
        return if @link.user_id == current_user.id

        render json: { error: "Unauthorized" }, status: :unauthorized
      end

      def serialize_log(log)
        {
          id: log.id,
          action: log.action,
          before_state: log.before_state,
          after_state: log.after_state,
          reason: log.reason,
          ip_address: log.ip_address,
          user: log.user&.email,
          created_at: log.created_at
        }
      end

      def pagination_meta(collection)
        {
          current_page: collection.current_page,
          total_pages: collection.total_pages,
          total_count: collection.total_count
        }
      end
    end
  end
end
