# frozen_string_literal: true

module Api
  module Levelcode
    module V1
      # Web access for the editor's agent (levelcode docs/WEB-SEARCH.md):
      #
      #   POST /api/levelcode/v1/ai/web/search  { queries: [..1-4], count?, recency? }  → results per query + credits
      #   POST /api/levelcode/v1/ai/web/fetch   { url }                                  → the page's text
      #
      # Search is billed like a model turn: the wallet is checked, the worst case (every query) reserved, the queries
      # that answered settled and written to the ledger as one row (model "web-search"), and the editor gets the same
      # `levelcode` credits object the chat stream ends with. Fetch is free, behind the same sign-in, agent scope and
      # per-minute cap as every gateway call; it exists because a browser tab cannot read another site itself.
      class AiWebController < BaseController
        before_action :require_agent_scope!

        def search
          queries = ::Levelcode::WebSearch.clean_queries(params[:queries])
          if queries.empty?
            return render_levelcode_error("invalid_request", "queries must hold 1-#{::Levelcode::WebSearch::MAX_QUERIES} search queries", :unprocessable_entity)
          end

          provider = ::Levelcode::WebSearch.provider
          return render_levelcode_error("web_search_unavailable", "Web search is not set up on LevelCode Cloud yet.", :service_unavailable) unless provider

          wallet = ::Levelcode::FreeTier.wallet_for(current_levelcode_user)
          decision = ::Levelcode::Metering.check!(wallet)
          # Over budget on a throttle plan keeps the cheap model running; a search costs real money per query, so it stops.
          return render_no_credits if decision.blocked? || decision.throttle

          per_query = ::Levelcode::WebSearch.cost_micros_per_query
          res = ::Levelcode::Metering.reserve!(wallet, queries.size * per_query)
          return render_no_credits unless res.ok

          reservation = res.amount
          settled = false
          begin
            count = params[:count].present? ? params[:count].to_i.clamp(1, ::Levelcode::WebSearch::MAX_COUNT) : ::Levelcode::WebSearch::DEFAULT_COUNT
            recency = ::Levelcode::WebSearch::RECENCY.include?(params[:recency].to_s) ? params[:recency].to_s : nil
            results = ::Levelcode::WebSearch.run(queries, provider: provider, count: count, recency: recency)
            cost = results.count { |r| r[:error].nil? } * per_query

            ::Levelcode::Metering.settle!(wallet, reservation, 0, 0, cost)
            settled = true
            if cost.positive?
              RecordUsageJob.perform_async(current_levelcode_user.id, SecureRandom.uuid, "web-search", provider.name,
                                           0, 0, 0, cost, wallet.period_end.to_i, Time.current.to_i)
            end
            render json: { results: results, levelcode: credits(wallet, cost) }
          ensure
            ::Levelcode::Metering.settle!(wallet, reservation, 0, 0, 0) unless settled # an exception releases the hold
          end
        end

        def fetch
          url = params[:url].to_s
          unless url.length <= 2048 && url.match?(%r{\Ahttps?://}i)
            return render_levelcode_error("invalid_request", "url must be an http or https address", :unprocessable_entity)
          end

          page = ::Levelcode::WebFetch.get(url)
          render json: page
        rescue ::Levelcode::WebFetch::Blocked => e
          render_levelcode_error("blocked", e.message, :unprocessable_entity)
        rescue ::Levelcode::WebFetch::NotText => e
          render_levelcode_error("not_text", e.message, :unsupported_media_type)
        rescue Net::OpenTimeout, Net::ReadTimeout
          render_levelcode_error("timeout", "The page did not answer in time.", :gateway_timeout)
        rescue SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError, URI::InvalidURIError => e
          render_levelcode_error("unreachable", "The page could not be reached (#{e.class.name.demodulize}).", :bad_gateway)
        end

        private

        # Web access is an agent capability: the same scope the gateway asks of a tool-calling turn.
        def require_agent_scope!
          scopes = (levelcode_token_claims && levelcode_token_claims["scope"].to_s.split(/\s+/)) || []
          return if scopes.include?("ai:agent")

          render_levelcode_error("insufficient_scope", "This token cannot use web access (missing ai:agent).", :forbidden)
        end

        def render_no_credits
          render_levelcode_error("cap_reached", "No credits left for web search in this period.", :payment_required)
        end

        # The same retail basis as the chat stream's credits frame (AiController#credits_frame).
        def credits(wallet, cost_micros)
          state = ::Levelcode::Metering.tranche_state(wallet)
          {
            cost_micros: ::Levelcode.retail_micros(cost_micros.to_i, wallet.plan_key),
            credits_remaining_micros: ::Levelcode.retail_micros(state[:remaining_micros].to_i, wallet.plan_key)
          }
        rescue => e
          Rails.logger.warn("[Api::Levelcode::V1::AiWebController] credits skipped: #{e.class}")
          nil
        end
      end
    end
  end
end
