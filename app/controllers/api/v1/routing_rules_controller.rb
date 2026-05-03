module Api
  module V1
    class RoutingRulesController < ApplicationController
      before_action :authenticate_user!
      skip_before_action :verify_authenticity_token
      before_action :set_link
      before_action :authorize_link!
      before_action :set_rule, only: %i[show update destroy]

      # GET /api/v1/links/:link_lookup_code/routing_rules
      def index
        @rules = @link.routing_rules.order(:priority).limit(100)

        render json: {
          routing_rules: @rules.map { |r| serialize_rule(r) }
        }
      end

      # GET /api/v1/links/:link_lookup_code/routing_rules/:id
      def show
        render json: serialize_rule(@rule)
      end

      # POST /api/v1/links/:link_lookup_code/routing_rules
      def create
        @rule = @link.routing_rules.build(rule_params)

        if @rule.save
          log_governance_event("rule_added", {}, rule_as_state(@rule))
          render json: serialize_rule(@rule), status: :created
        else
          render json: { errors: @rule.errors.full_messages }, status: :unprocessable_content
        end
      end

      # PATCH /api/v1/links/:link_lookup_code/routing_rules/:id
      def update
        before = rule_as_state(@rule)

        if @rule.update(rule_params)
          log_governance_event("rule_updated", before, rule_as_state(@rule))
          render json: serialize_rule(@rule)
        else
          render json: { errors: @rule.errors.full_messages }, status: :unprocessable_content
        end
      end

      # DELETE /api/v1/links/:link_lookup_code/routing_rules/:id
      def destroy
        log_governance_event("rule_removed", rule_as_state(@rule), {})
        @rule.destroy!
        head :no_content
      end

      private

      def set_link
        @link = Link.find_by!(lookup_code: params[:link_lookup_code])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Link not found" }, status: :not_found
      end

      def authorize_link!
        return if @link.user_id == current_user.id

        render json: { error: "Unauthorized" }, status: :unauthorized
      end

      def set_rule
        @rule = @link.routing_rules.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Routing rule not found" }, status: :not_found
      end

      def rule_params
        params.require(:routing_rule).permit(
          :rule_type, :destination_url, :weight, :priority, :active,
          conditions: {}
        )
      end

      def serialize_rule(rule)
        {
          id: rule.id,
          rule_type: rule.rule_type,
          conditions: rule.conditions,
          destination_url: rule.destination_url,
          weight: rule.weight,
          priority: rule.priority,
          active: rule.active,
          created_at: rule.created_at,
          updated_at: rule.updated_at
        }
      end

      def rule_as_state(rule)
        { rule_type: rule.rule_type, destination_url: rule.destination_url, conditions: rule.conditions }
      end

      def log_governance_event(action, before_state, after_state)
        @link.governance_logs.create!(
          user: current_user,
          action: action,
          before_state: before_state,
          after_state: after_state,
          ip_address: request.remote_ip
        )
      end
    end
  end
end
