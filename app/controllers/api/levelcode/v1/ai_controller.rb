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

          # Reserve this request's worst-case cost against the dollar budget BEFORE it runs, so a burst
          # of concurrent streams can't collectively overshoot the budget in the window before their
          # spend lands (spend is only recorded after each stream closes). Skip on the throttle path —
          # it runs the near-free open-weights engine intentionally and isn't budget-metered. A
          # reservation that would exceed the budget → 402 (same surface as a cap hit).
          reservation = 0
          estimate = 0
          unless decision.throttle
            free_tier = wallet.plan_key.to_s == ::Levelcode::FREE_PLAN_KEY
            estimate = ::Levelcode.estimate_cost_micros(model, body, free_tier: free_tier)
            res = ::Levelcode::Metering.reserve!(wallet, estimate)
            return render_cap_reached(wallet) unless res.ok

            reservation = res.amount
          end

          if streaming?(body)
            stream_chat(body, wallet, model, reservation, estimate)
          else
            complete_chat(body, wallet, model, reservation)
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

        def stream_chat(body, wallet, model, reservation, estimate)
          response.headers["Content-Type"] = "text/event-stream"
          response.headers["Cache-Control"] = "no-cache"
          response.headers["X-Accel-Buffering"] = "no" # disable proxy buffering
          response.headers.delete("Content-Length")

          request_id = current_request_id
          @captured_usage = nil
          @captured_model = nil
          @streamed_content = false

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
            klass = classify_upstream(e)
            log_upstream(e, klass)
            write_sse(upstream_error_json(klass))
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
            # Settle the reservation + meter the turn exactly once, even on a mid-stream disconnect
            # (SPEC §5), so tokens already consumed upstream still count and the reservation is never
            # stranded.
            finalize_stream!(wallet, request_id, reservation, model, estimate)
            close_stream
          end
        end

        # OpenRouter emits the final usage/model object as a chunk before [DONE]. Capture it off the tee
        # so metering survives a client disconnect, and note whether any CONTENT was streamed (so a
        # hang-up before the final usage chunk can be charged rather than billed $0).
        def capture_usage(payload)
          data = JSON.parse(payload)
          @captured_usage = data["usage"] if data["usage"].present?
          @captured_model = data["model"] if data["model"].present?
          @streamed_content = true if streamed_content?(data)
        rescue JSON::ParserError
          nil
        end

        def streamed_content?(data)
          Array(data["choices"]).any? do |c|
            c.is_a?(Hash) && (c.dig("delta", "content").to_s != "" || c.dig("message", "content").to_s != "")
          end
        end

        # Settle the reservation + meter the turn exactly once, whatever happened to the stream:
        #  • usage captured  → bill the REAL cost (and release the over-reserved remainder).
        #  • no usage but content WAS streamed (client hung up before the final usage chunk) → tokens
        #    were produced upstream, so don't zero-bill: charge the reserved estimate + write a
        #    synthetic ledger row so the durable column matches the hot counter.
        #  • no usage and nothing streamed (pure upstream error / instant disconnect) → release it.
        def finalize_stream!(wallet, request_id, reservation, model, estimate)
          if @captured_usage.present?
            meter!(
              wallet,
              ::Levelcode::OpenRouterAdapter::Result.new(usage: @captured_usage, model: @captured_model),
              request_id, reservation, model
            )
          elsif @streamed_content
            # Tokens were produced upstream but the usage chunk never arrived (client hung up). Charge
            # the reserved estimate; if the reservation failed OPEN (amount 0 on a Redis blip at
            # admission), fall back to a fresh estimate so a disconnect-after-output is never billed $0.
            charge = reservation.to_i.positive? ? reservation.to_i : estimate.to_i
            if charge.positive?
              charge_reservation!(wallet, request_id, reservation, charge, model)
            else
              ::Levelcode::Metering.settle!(wallet, reservation, 0, 0, 0)
            end
          else
            ::Levelcode::Metering.settle!(wallet, reservation, 0, 0, 0) # release the reservation
          end
        rescue => e
          Rails.logger.error("[Api::Levelcode::V1::AiController] finalize failed: #{e.class}: #{e.message}")
        end

        # Client disconnected mid-stream after tokens were produced but before the usage chunk: bill
        # `charge` (the standing reservation, or a fresh estimate if the reservation failed open) and
        # write a synthetic ledger row so durable spend matches the hot counter. `reservation` is what's
        # already on the hot counter, so settle! reconciles it to `charge` (delta = charge − reservation).
        def charge_reservation!(wallet, request_id, reservation, charge, billing_model)
          ::Levelcode::Metering.settle!(wallet, reservation, 0, 0, charge)
          RecordUsageJob.perform_async(
            current_levelcode_user.id, request_id, billing_model, PROVIDER,
            0, 0, 0, charge.to_i, wallet.period_end.to_i
          )
        end

        # -- non-streaming (JSON pass-through) path -------------------------

        def complete_chat(body, wallet, model, reservation)
          request_id = current_request_id
          settled = false
          upstream = ::Levelcode::AiRouter.complete(body, model: model)
          meter!(wallet, ::Levelcode::OpenRouterAdapter::Result.new(usage: upstream["usage"], model: upstream["model"]), request_id, reservation, model)
          settled = true # meter! has reconciled/released the reservation; don't touch it again below
          render json: upstream, status: :ok
        rescue ::Levelcode::OpenRouterAdapter::UpstreamError => e
          ::Levelcode::Metering.settle!(wallet, reservation, 0, 0, 0) unless settled # no generation → release
          klass = classify_upstream(e)
          log_upstream(e, klass)
          render json: { error: { code: klass[:code], message: klass[:message] } }, status: klass[:http]
        rescue => e
          # Any OTHER failure (timeout, connection reset, malformed upstream JSON) before meter! settled
          # would STRAND the reservation (spend over-counted) — release it. `settled` guards against a
          # double-release if the failure happened after meter! already reconciled.
          ::Levelcode::Metering.settle!(wallet, reservation, 0, 0, 0) unless settled
          Rails.logger.error("[Api::Levelcode::V1::AiController] complete error: #{e.class}: #{e.message}")
          render json: { error: { code: "gateway_error", message: "gateway_error" } }, status: :bad_gateway
        end

        # -- metering tee ----------------------------------------------------

        # Reconcile the reservation to the real spend + write the durable ledger row. `billing_model` is
        # the ROUTED catalog model (what we price/entitle), NOT result.model — the upstream string is
        # often a dated snapshot ("…-20260528") that's absent from the catalog and would fall back to
        # the cheapest rate, under-billing pricier models. The ledger still RECORDS the served id.
        def meter!(wallet, result, request_id, reservation, billing_model)
          usage = result&.usage
          usage = nil unless usage.is_a?(Hash) # a non-Hash usage (malformed upstream) must not raise below
          if usage.blank?
            ::Levelcode::Metering.settle!(wallet, reservation, 0, 0, 0) # nothing to bill → release
            return
          end

          input_tokens = (usage["prompt_tokens"] || usage[:prompt_tokens]).to_i
          output_tokens = (usage["completion_tokens"] || usage[:completion_tokens]).to_i
          cached = cached_tokens(usage)
          cost_micros = ::Levelcode.cost_micros(billing_model, input_tokens, output_tokens, cached)
          ledger_model = result.model.presence || billing_model

          # Reconcile the up-front reservation to the actual cost (M14) + keep the token counters.
          ::Levelcode::Metering.settle!(wallet, reservation, input_tokens, output_tokens, cost_micros)

          RecordUsageJob.perform_async(
            current_levelcode_user.id,
            request_id,
            ledger_model,
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
          free  = wallet.plan_key.to_s == ::Levelcode::FREE_PLAN_KEY
          state = ::Levelcode::Metering.tranche_state(wallet)
          # A rolling-window gate (more unlocks soon) is NOT the monthly cap — say so, and don't sell an
          # upgrade for a wait. Only fires when tranching is on; otherwise it's the plain period message.
          window_gated = state[:kind] == :window_exhausted && state[:next_unlock_at].present?

          message =
            if window_gated
              "You've used the usage available right now. More unlocks #{state[:next_unlock_at].strftime('%b %-d')}."
            elsif free
              "You've reached this month's free compute limit. Upgrade to Pro to unlock Kimi K2.7 Code — a sharper coding model — and much higher limits, so you can keep building without interruption."
            else
              "You've reached your plan's usage limit for this billing period. It resets on your next renewal — or manage your plan to raise it."
            end

          render json: {
            error: {
              code: "cap_reached",
              message: message,
              # The editor surfaces this as an "Upgrade" CTA on the free tier — but not for a rolling-window wait.
              upgrade_url: (free && !window_gated ? "#{site_origin}/ai/pricing" : nil),
              topup_url: topup_url_for(wallet),
              next_unlock_at: (window_gated ? state[:next_unlock_at] : nil)
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

        def upstream_error_json(klass)
          { error: { code: klass[:code], message: klass[:message] } }.to_json
        end

        # User-facing copy for upstream failures. Deliberately generic — NO provider name,
        # token math, credits URL, or upstream status number ever reaches the client.
        SERVICE_UNAVAILABLE_MSG =
          "The AI service is temporarily unavailable. This is on our side — not your " \
          "account or your usage. Please try again in a moment.".freeze
        SERVICE_BUSY_MSG =
          "The AI service is busy right now. Please wait a moment and try again.".freeze
        INPUT_FLAGGED_MSG =
          "This request was blocked by the model's content filter. Try rephrasing your " \
          "prompt and send again.".freeze
        CONTEXT_LENGTH_MSG =
          "This conversation is too long for the model's context window. Start a new chat, " \
          "remove some pinned files, or switch to a larger-context model.".freeze

        # Map a raw UpstreamError to a SAFE, classified editor error. The raw body is read
        # here ONLY to classify + log — it is NEVER returned to the client. Anything not
        # positively identified as a user-side condition is treated as an our-side outage
        # (fail safe), so a new/unknown upstream error can never leak internal structure.
        def classify_upstream(error)
          status = error.status.to_i
          low    = error.body.to_s.downcase

          if status == 403 && low.include?("flag") # content moderation (user-side)
            return { code: "input_flagged", message: INPUT_FLAGGED_MSG, http: :bad_request, alert: false }
          end
          if status == 400 && low.match?(/context (length|window)|maximum context/) # user-side
            return { code: "context_length", message: CONTEXT_LENGTH_MSG, http: :bad_request, alert: false }
          end
          if status == 429 # upstream throttle (transient)
            return { code: "service_busy", message: SERVICE_BUSY_MSG, http: :service_unavailable, alert: false }
          end

          # credits(402) / auth(401) / bad-model-id(404) / provider outage / unknown → one
          # generic ops-safe message. ALERT only on the classes that mean PAID AI is globally
          # down (platform balance, bad key, bad model id) — not on client-malformed 400s.
          { code: "service_unavailable", message: SERVICE_UNAVAILABLE_MSG, http: :service_unavailable,
            alert: [ 401, 402, 404 ].include?(status) }
        end

        # Log the raw upstream detail for us (never sent to the client). Page-worthy classes
        # go to error with a greppable [LEVELCODE_ALERT] tag; user-side/transient stay at warn.
        def log_upstream(error, klass)
          detail = "upstream #{error.status} -> #{klass[:code]}: #{error.body.to_s[0, 800]}"
          if klass[:alert]
            Rails.logger.error("[LEVELCODE_ALERT] [Api::Levelcode::V1::AiController] #{detail}")
          else
            Rails.logger.warn("[Api::Levelcode::V1::AiController] #{detail}")
          end
        end

        # Mint a fresh SERVER-side idempotency/billing id per turn. Deriving it from request.request_id
        # would trust the client-controlled X-Request-Id header — a client could reuse one id across
        # turns and collapse them onto a single durable ledger row (spend under-counts, a real bypass
        # once Redis is cold). request.request_id stays for log correlation only.
        def current_request_id
          SecureRandom.uuid
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
