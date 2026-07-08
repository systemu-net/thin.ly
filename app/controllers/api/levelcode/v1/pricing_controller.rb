module Api
  module Levelcode
    module V1
      # Public pricing endpoint — server-side truth for the 4 Levelcode tiers.
      # The site (levelcode.ai/pricing) and editor render whatever this returns;
      # prices/caps are never hard-coded on the frontend (SPEC §3, §6, D10).
      class PricingController < BaseController
        skip_before_action :authenticate_levelcode!, only: %i[index]

        # GET /api/levelcode/v1/pricing
        def index
          render json: { tiers: serialized_tiers }, status: :ok
        end

        private

        def serialized_tiers
          ::Levelcode::PLANS.map do |plan|
            {
              key: plan[:key],
              name: plan[:name],
              price_cents: plan[:price_cents],
              interval: plan[:interval] || "month",
              input_cap: plan[:input_cap],
              output_cap: plan[:output_cap],
              turns: plan[:turns],
              features: plan[:features] || []
            }
          end
        end
      end
    end
  end
end
