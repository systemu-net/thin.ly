module Api
  module Levelcode
    module V1
      # Account surface for the levelcode product (SPEC §3).
      # Both actions require a valid editor access token or web session
      # (authenticate_levelcode! is enforced by BaseController).
      class AccountController < BaseController
        PRODUCT = "levelcode".freeze

        # GET /api/levelcode/v1/account/profile
        def profile
          render json: {
            id: current_user.id,
            email: current_user.email,
            name: display_name,
            plan: current_plan_name,
            role: current_user.role
          }, status: :ok
        end

        # GET /api/levelcode/v1/account/usage
        def usage
          wallet = current_wallet
          # Show the LIVE per-period spend/usage (the same counters enforcement uses),
          # not the async-lagged wallet columns.
          in_used, out_used = wallet ? ::Levelcode::Metering.usage(wallet) : [ 0, 0 ]
          state = wallet ? ::Levelcode::Metering.tranche_state(wallet) : nil

          render json: {
            plan: current_plan_name,
            model: ::Levelcode.gateway_model(wallet&.plan_key),
            # Credits (M14): the DOLLAR budget is the enforced allowance; token fields are informational.
            # These four figures are RETAIL micro-$ — what the customer PAID (cost ÷ margin), not the
            # internal cost budget — so a $40 plan reads "$40" here while metering/enforcement stay in
            # cost dollars and "≈ turns left" (below) is unaffected. See Levelcode.retail_micros.
            # budget_micros is the full monthly allowance; credits_remaining_micros is measured against
            # the currently-UNLOCKED ceiling (rolling usage windows) so the UI never shows more than
            # enforcement will actually serve. next_unlock_at is when more unlocks (nil if all is, or
            # tranching is off). With tranching disabled these equal the full-budget values as before.
            budget_micros: state ? retail(state[:full_micros]) : 0,
            ceiling_micros: state ? retail(state[:ceiling_micros]) : 0,
            spent_micros: state ? retail(state[:spent_micros]) : 0,
            credits_remaining_micros: state ? retail(state[:remaining_micros]) : 0,
            next_unlock_at: state ? state[:next_unlock_at] : nil,
            input_used: in_used,
            input_cap: wallet&.input_cap.to_i,
            output_used: out_used,
            output_cap: wallet&.output_cap.to_i,
            period_end: wallet&.period_end,
            overage_policy: wallet&.overage_policy || "throttle"
          }, status: :ok
        end

        # GET /api/levelcode/v1/account/models
        # The plan's model roster for the editor picker + dashboard (M14 Phase 3): every entitled
        # model with its credit multiplier, ≈ turns left on the current balance, and a `live` flag
        # (confirmed-price models are selectable; staged ones are shown but not yet billable).
        def models
          wallet = current_wallet
          state = wallet ? ::Levelcode::Metering.tranche_state(wallet) : nil
          # turns-left is computed from what's usable NOW (the unlocked ceiling), not the full budget.
          # Keep this in COST micro-$ — roster_for divides it by each model's real per-turn cost, so the
          # turns are margin-independent. Only the customer-facing dollar figures are shown at RETAIL.
          remaining = state ? state[:remaining_micros] : 0

          render json: {
            plan: current_plan_name,
            default_model: ::Levelcode.default_model(current_plan_key),
            # Retail micro-$ (what the customer paid) — see #usage + Levelcode.retail_micros.
            budget_micros: state ? retail(state[:full_micros]) : 0,
            ceiling_micros: state ? retail(state[:ceiling_micros]) : 0,
            spent_micros: state ? retail(state[:spent_micros]) : 0,
            credits_remaining_micros: retail(remaining),
            next_unlock_at: state ? state[:next_unlock_at] : nil,
            models: ::Levelcode.roster_for(current_plan_key, remaining)
          }, status: :ok
        end

        # GET /api/levelcode/v1/account/activity?year=YYYY
        # GitHub-style contribution data: per-day editor usage + a per-model breakdown,
        # from the durable usage_events ledger. `year` defaults to the current year.
        def activity
          year = (params[:year].presence || Time.current.year).to_i
          # plan_key makes the per-model/day costs RETAIL — the same unit as the balance on this page.
          render json: ::Levelcode::Activity.for_user(current_user, year: year, plan_key: current_plan_key),
                 status: :ok
        end

        private

        # Free-tier aware: a logged-in user with no paid plan gets (and sees) the
        # FREE tier — FreeTier provisions/rolls a free wallet so the dashboard shows
        # the free caps + gpt-oss engine instead of a blank "no plan".
        def current_wallet
          ::Levelcode::FreeTier.wallet_for(current_user)
        end

        def current_plan_key
          current_wallet&.plan_key || "free"
        end

        # Present an internal COST micro-$ figure as the RETAIL amount the customer paid (cost ÷ margin
        # for a paid plan; unchanged for free). See Levelcode.retail_micros.
        def retail(cost_micros)
          ::Levelcode.retail_micros(cost_micros, current_plan_key)
        end

        # Friendly plan label for display (e.g. "Pro") — the Levelcode plan NAME, not the
        # raw key ("orbits_pro"). "Free" when there's no active managed plan (BYOK).
        def current_plan_name
          key = current_wallet&.plan_key
          return "Free" if key.blank? || key == "free"

          ::Levelcode.plan(key)&.dig(:name) || key
        end

        # `name` is provided by the auth slice; fall back to the profile
        # display name (every user has a profile) so this never 500s.
        def display_name
          if current_user.respond_to?(:name) && current_user.name.present?
            current_user.name
          else
            current_user.profile&.display_name
          end
        end
      end
    end
  end
end
