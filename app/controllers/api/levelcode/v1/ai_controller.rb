module Api
  module Levelcode
    module V1
      # POST /api/levelcode/v1/ai/chat — the gateway (SPEC §4/§5/§7).
      #
      # Transparent proxy of OpenRouter's OpenAI-compatible /chat/completions
      # stream: each upstream chunk is re-emitted verbatim as an SSE `data:`
      # line, terminated by `data: [DONE]`. The only thing we do beyond piping
      # is (a) enforce caps before the request and (b) tee the final `usage`
      # object into metering after the stream closes.
      class AiController < BaseController
        include ActionController::Live

        before_action :authenticate_levelcode!
        before_action :require_ai_scope!

        PROVIDER = "openrouter".freeze

        def chat
          # Entitlement (M11): a PAID plan runs the flagship (Kimi K2.7 Code); ANY
          # other logged-in editor user gets the FREE tier — the cheap open-weights
          # engine (gpt-oss-120b) on a hard monthly cap. FreeTier provisions/rolls a
          # free wallet as the metering anchor; it never touches a paid plan. (BYOK
          # stays the free-and-private path and never reaches the gateway.)
          wallet = ::Levelcode::FreeTier.wallet_for(current_levelcode_user)

          decision = ::Levelcode::Metering.check!(wallet)
          return render_cap_reached(wallet) if decision.blocked?

          raw = chat_params
          # Over-budget on a THROTTLE plan → fall back to the cheap open-weights engine so the user
          # keeps working at near-zero marginal cost (M14). Otherwise honor the editor's requested
          # model IF the plan is entitled to it (a Pro user may pick gpt-oss too), else the plan
          # default. Entitlement stays server-side — free can never reach the flagship.
          model =
            if decision.throttle
              ::Levelcode::FREE_MODEL
            elsif raw["model"].to_s == ::Levelcode::AUTO_MODEL
              ::Levelcode.auto_route(wallet.plan_key, raw) # cheap engine for trivial turns, else plan default
            else
              ::Levelcode.gateway_model(wallet.plan_key, raw["model"])
            end
          # Per-request output ceiling: the FREE ceiling when free OR throttled (running the cheap
          # engine), else the higher paid ceiling — bounds a single request's spend so concurrent
          # streams can't overshoot the dollar budget before their spend lands.
          body = cap_output(raw, wallet, throttled: decision.throttle)

          if streaming?(body)
            stream_chat(body, wallet, model)
          else
            complete_chat(body, wallet, model)
          end
        end

        private

        # The editor token must carry an inference scope to use the gateway.
        # Agent turns (tool-calling — the premium capability) require ai:agent;
        # plain chat requires ai:chat. Whether the USER's plan may use agent is a
        # separate entitlement check (plan-gating) — not the token scope.
        def require_ai_scope!
          needed = agent_turn? ? "ai:agent" : "ai:chat"
          scopes = (levelcode_token_claims && levelcode_token_claims["scope"].to_s.split(/\s+/)) || []
          return if scopes.include?(needed)

          render_levelcode_error(
            "insufficient_scope",
            "This token cannot make #{agent_turn? ? 'agent' : 'chat'} requests (missing #{needed}).",
            :forbidden
          )
        end

        # An agent turn carries tool definitions (function calling); plain chat does not.
        def agent_turn?
          params[:tools].present?
        end

        # -- streaming (SSE) path -------------------------------------------

        def stream_chat(body, wallet, model)
          response.headers["Content-Type"] = "text/event-stream"
          response.headers["Cache-Control"] = "no-cache"
          response.headers["X-Accel-Buffering"] = "no" # disable proxy buffering
          response.headers.delete("Content-Length")

          request_id = current_request_id
          @captured_usage = nil
          @captured_model = nil

          begin
            result = ::Levelcode::AiRouter.call(
              body,
              model: model,
              on_chunk: ->(payload) { capture_usage(payload); write_sse(payload) }
            )
            @captured_usage ||= result&.usage
            @captured_model ||= result&.model
            write_raw("data: [DONE]\n\n")
          rescue ::Levelcode::OpenRouterAdapter::UpstreamError => e
            Rails.logger.warn("[Api::Levelcode::V1::AiController] upstream #{e.status}: #{e.body.to_s[0, 800]}")
            write_sse(upstream_error_json(e))
          rescue IOError, ActionController::Live::ClientDisconnected
            # Client hung up mid-stream; nothing more to write.
            Rails.logger.info("[Api::Levelcode::V1::AiController] client disconnected mid-stream")
          rescue => e
            Rails.logger.error("[Api::Levelcode::V1::AiController] stream error: #{e.class}: #{e.message}")
            begin
              write_sse({ error: { message: "gateway_error", code: "gateway_error" } }.to_json)
            rescue IOError
              nil
            end
          ensure
            # Meter whatever usage we captured — even on a mid-stream disconnect —
            # so tokens already consumed upstream still count against caps + billing
            # (SPEC §5). Runs exactly once (metering only records non-zero usage).
            meter_captured!(wallet, request_id)
            close_stream
          end
        end

        # OpenRouter emits the final usage/model object as a chunk before [DONE].
        # Capture it off the tee so metering survives a client disconnect.
        def capture_usage(payload)
          data = JSON.parse(payload)
          @captured_usage = data["usage"] if data["usage"].present?
          @captured_model = data["model"] if data["model"].present?
        rescue JSON::ParserError
          nil
        end

        def meter_captured!(wallet, request_id)
          return if @captured_usage.blank?

          meter!(
            wallet,
            ::Levelcode::OpenRouterAdapter::Result.new(usage: @captured_usage, model: @captured_model),
            request_id
          )
        end

        # -- non-streaming (JSON pass-through) path -------------------------

        def complete_chat(body, wallet, model)
          request_id = current_request_id
          upstream = ::Levelcode::AiRouter.complete(body, model: model)
          meter!(wallet, ::Levelcode::OpenRouterAdapter::Result.new(usage: upstream["usage"], model: upstream["model"]), request_id)
          render json: upstream, status: :ok
        rescue ::Levelcode::OpenRouterAdapter::UpstreamError => e
          Rails.logger.warn("[Api::Levelcode::V1::AiController] upstream #{e.status}: #{e.body.to_s[0, 800]}")
          render json: { error: { code: "upstream_error", message: upstream_message(e) } },
                 status: :bad_gateway
        end

        # -- metering tee ----------------------------------------------------

        def meter!(wallet, result, request_id)
          usage = result&.usage
          return if usage.blank?

          input_tokens = (usage["prompt_tokens"] || usage[:prompt_tokens]).to_i
          output_tokens = (usage["completion_tokens"] || usage[:completion_tokens]).to_i
          cached = cached_tokens(usage)
          model = result.model
          cost_micros = ::Levelcode.cost_micros(model, input_tokens, output_tokens, cached)

          # Burn the DOLLAR budget by this request's cost (M14) + keep the token counters for display.
          ::Levelcode::Metering.record(wallet, input_tokens, output_tokens, cost_micros)

          RecordUsageJob.perform_async(
            current_levelcode_user.id,
            request_id,
            model,
            PROVIDER,
            input_tokens,
            output_tokens,
            cached,
            cost_micros,
            wallet.period_end.to_i # period at enqueue — scopes the durable counter to the right period
          )
        rescue => e
          Rails.logger.error("[Api::Levelcode::V1::AiController] metering tee failed: #{e.class}: #{e.message}")
        end

        def cached_tokens(usage)
          details = usage["prompt_tokens_details"] || usage[:prompt_tokens_details] || {}
          (details["cached_tokens"] || details[:cached_tokens]).to_i
        end

        # -- helpers ---------------------------------------------------------

        def streaming?(body)
          val = body["stream"]
          val = body[:stream] if val.nil?
          ActiveModel::Type::Boolean.new.cast(val)
        end

        def write_sse(payload)
          write_raw("data: #{payload}\n\n")
        end

        def write_raw(data)
          response.stream.write(data)
        end

        def close_stream
          response.stream.close
        rescue IOError
          nil
        end

        def render_cap_reached(wallet)
          free = wallet.plan_key.to_s == ::Levelcode::FREE_PLAN_KEY
          render json: {
            error: {
              code: "cap_reached",
              message: free ?
                "You've hit your free monthly limit. Upgrade to Pro for Kimi K2.7 Code and higher caps." :
                "Usage cap reached for the current billing period.",
              # The editor surfaces this as an "Upgrade" CTA on the free tier.
              upgrade_url: (free ? "#{site_origin}/ai/pricing" : nil),
              topup_url: topup_url_for(wallet)
            }
          }, status: :payment_required
        end

        def topup_url_for(wallet)
          return nil unless wallet.overage_policy == "topup"

          "#{site_origin}/ai/account"
        end

        def site_origin
          ENV["SITE_ORIGIN"].presence || "https://levelcode.ai"
        end

        def upstream_error_json(error)
          { error: { code: "upstream_error", status: error.status, message: upstream_message(error) } }.to_json
        end

        # Surface the REAL upstream reason (the OpenRouter error message) instead of
        # a generic label — e.g. "moonshotai/kimi-k2.6 is not a valid model ID" or
        # "No auth credentials found" — so failures are diagnosable in the editor.
        def upstream_message(error)
          parsed = JSON.parse(error.body.to_s)
          msg = parsed.dig("error", "message") || parsed["message"]
          msg.presence || "Upstream returned #{error.status}"
        rescue JSON::ParserError, TypeError
          "Upstream returned #{error.status}"
        end

        def current_request_id
          request.request_id || SecureRandom.uuid
        end

        # Passes the OpenAI chat body through untouched. We permit the whole
        # payload because this is a transparent proxy — we must not drop fields
        # the editor/upstream rely on.
        def chat_params
          params.permit!.to_h.except("controller", "action", "ai", "format")
        end

        # Per-request output ceiling (M14). Enforcement is per-request-start, so without a per-request
        # bound a burst of concurrent streams could overshoot the dollar budget before their spend
        # lands. Clamps an over-large client value AND sets a default when omitted. The FREE ceiling
        # applies to free wallets OR the throttle path (both run the cheap engine); paid requests get
        # the higher paid ceiling.
        def cap_output(body, wallet, throttled: false)
          free_ceiling = throttled || wallet.plan_key.to_s == ::Levelcode::FREE_PLAN_KEY
          limit = free_ceiling ? ::Levelcode::FREE_MAX_TOKENS : ::Levelcode::PAID_MAX_TOKENS

          out = body.dup
          fields = %w[max_tokens max_completion_tokens].select { |f| out[f].present? }
          if fields.empty?
            out["max_tokens"] = limit
          else
            fields.each { |f| out[f] = [ out[f].to_i, limit ].min }
          end
          out
        end
      end
    end
  end
end
