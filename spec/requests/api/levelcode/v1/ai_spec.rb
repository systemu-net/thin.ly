require 'rails_helper'

# Gateway request spec (SPEC §4/§5/§7). The upstream adapter is stubbed to emit
# canned SSE chunks so we assert (a) the transparent SSE shape and (b) that the
# final usage is teed into metering. Cross-slice collaborators owned by the auth
# and data slices (BaseController#authenticate_levelcode!, current_levelcode_user,
# CreditWallet.for, Levelcode.cost_micros) are stubbed at their interfaces.
RSpec.describe "Api::Levelcode::V1::Ai", type: :request do
  let(:user) { create(:user) }

  # A minimal wallet double matching the CreditWallet interface the controller
  # and Levelcode::Metering rely on.
  let(:wallet) do
    instance_double(
      "CreditWallet",
      user_id: user.id,
      plan_key: "orbits_pro",
      input_cap: 15_000_000,
      output_cap: 2_000_000,
      input_used: 0,
      output_used: 0,
      period_start: Time.current.beginning_of_month,
      period_end: Time.current.end_of_month,
      overage_policy: "throttle"
    )
  end

  let(:canned_chunks) do
    [
      '{"choices":[{"index":0,"delta":{"content":"Hel"}}]}',
      '{"choices":[{"index":0,"delta":{"content":"lo"}}]}',
      '{"choices":[{"index":0,"delta":{}}],"usage":{"prompt_tokens":12,"completion_tokens":8,"prompt_tokens_details":{"cached_tokens":4}}}'
    ]
  end

  let(:final_usage) do
    { "prompt_tokens" => 12, "completion_tokens" => 8, "prompt_tokens_details" => { "cached_tokens" => 4 } }
  end

  before do
    # Auth slice: treat the request as authenticated with a full-scope token.
    allow_any_instance_of(Api::Levelcode::V1::AiController)
      .to receive(:authenticate_levelcode!).and_return(true)
    allow_any_instance_of(Api::Levelcode::V1::AiController)
      .to receive(:current_levelcode_user).and_return(user)
    allow_any_instance_of(Api::Levelcode::V1::AiController)
      .to receive(:levelcode_token_claims).and_return("scope" => "ai:chat ai:agent account:read")

    # Tier resolution (M11): FreeTier returns the paid wallet (this double) for a
    # paid user, or a free wallet otherwise. Stub it to the paid wallet by default.
    allow(Levelcode::FreeTier).to receive(:wallet_for).with(user).and_return(wallet)

    # Cost table is a data-slice concern; keep it deterministic here.
    allow(Levelcode).to receive(:cost_micros).and_return(1_000)

    # Redis hot counters — assert on record without a live Redis.
    allow(Levelcode::Metering).to receive(:check!).and_call_original
  end

  def stub_streaming_adapter
    allow_any_instance_of(Levelcode::OpenRouterAdapter).to receive(:stream) do |_adapter, _body, on_chunk:|
      canned_chunks.each { |c| on_chunk.call(c) }
      Levelcode::OpenRouterAdapter::Result.new(usage: final_usage, model: ENV.fetch("LEVELCODE_MODEL", "moonshotai/kimi-k2.6"))
    end
  end

  describe "POST /api/levelcode/v1/ai/chat (stream)" do
    let(:body) do
      { model: "moonshotai/kimi-k2.6", stream: true, stream_options: { include_usage: true },
        messages: [ { role: "user", content: "hi" } ] }
    end

    before do
      allow(Levelcode::Metering).to receive(:check!)
        .and_return(Levelcode::Metering::Decision.new(allowed: true, throttle: false, policy: "throttle"))
      stub_streaming_adapter
    end

    it "streams upstream chunks verbatim as SSE and terminates with [DONE]" do
      post "/api/levelcode/v1/ai/chat", params: body, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to include("text/event-stream")

      canned_chunks.each do |chunk|
        expect(response.body).to include("data: #{chunk}\n\n")
      end
      expect(response.body).to include("data: [DONE]\n\n")
    end

    it "tees the final usage into Redis metering (tokens + $ spend) and the durable ledger" do
      expect(Levelcode::Metering).to receive(:record).with(wallet, 12, 8, 1_000) # 4th arg = cost_micros
      expect(RecordUsageJob).to receive(:perform_async)
        .with(user.id, anything, kind_of(String), "openrouter", 12, 8, 4, 1_000, kind_of(Integer))

      post "/api/levelcode/v1/ai/chat", params: body, as: :json
    end
  end

  describe "POST /api/levelcode/v1/ai/chat when cap reached" do
    let(:body) { { model: "moonshotai/kimi-k2.6", stream: true, messages: [] } }

    it "returns 402 cap_reached for a topup wallet" do
      topup_wallet = instance_double(
        "CreditWallet", user_id: user.id, plan_key: "orbits_pro", input_cap: 1, output_cap: 1,
        input_used: 5, output_used: 5, period_start: Time.current, period_end: Time.current,
        overage_policy: "topup"
      )
      allow(Levelcode::FreeTier).to receive(:wallet_for).and_return(topup_wallet)
      allow(Levelcode::Metering).to receive(:check!)
        .and_return(Levelcode::Metering::Decision.new(allowed: false, throttle: false, policy: "topup"))

      post "/api/levelcode/v1/ai/chat", params: body, as: :json

      expect(response).to have_http_status(:payment_required)
      json = JSON.parse(response.body)
      expect(json.dig("error", "code")).to eq("cap_reached")
      expect(json.dig("error", "topup_url")).to be_present
    end
  end

  describe "scope enforcement (ai:chat vs ai:agent)" do
    before do
      allow(Levelcode::Metering).to receive(:check!)
        .and_return(Levelcode::Metering::Decision.new(allowed: true, throttle: false, policy: "throttle"))
      stub_streaming_adapter
    end

    def with_scope(scope)
      allow_any_instance_of(Api::Levelcode::V1::AiController)
        .to receive(:levelcode_token_claims).and_return("scope" => scope)
    end

    it "allows an agent turn (tools present) with ai:agent" do
      with_scope("ai:chat ai:agent account:read")
      post "/api/levelcode/v1/ai/chat",
           params: { model: "x", stream: true, tools: [ { type: "function" } ], messages: [] }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "REJECTS an agent turn with a chat-only token (missing ai:agent)" do
      with_scope("ai:chat account:read")
      post "/api/levelcode/v1/ai/chat",
           params: { model: "x", stream: true, tools: [ { type: "function" } ], messages: [] }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body).dig("error", "code")).to eq("insufficient_scope")
    end

    it "allows plain chat with a chat-only token" do
      with_scope("ai:chat account:read")
      post "/api/levelcode/v1/ai/chat",
           params: { model: "x", stream: true, messages: [ { role: "user", content: "hi" } ] }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "REJECTS the gateway for a web-session token (account:read only)" do
      with_scope("account:read")
      post "/api/levelcode/v1/ai/chat", params: { model: "x", stream: true, messages: [] }, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/levelcode/v1/ai/chat on the FREE tier (M11)" do
    let(:free_wallet) do
      instance_double(
        "CreditWallet", user_id: user.id, plan_key: "free",
        input_cap: Levelcode::FREE_INPUT_CAP, output_cap: Levelcode::FREE_OUTPUT_CAP,
        input_used: 0, output_used: 0, period_start: Time.current, period_end: 1.month.from_now,
        overage_policy: "stop"
      )
    end

    before { allow(Levelcode::FreeTier).to receive(:wallet_for).and_return(free_wallet) }

    it "serves gpt-oss-120b (not 402) and FORCES the free engine regardless of the requested model" do
      allow(Levelcode::Metering).to receive(:check!)
        .and_return(Levelcode::Metering::Decision.new(allowed: true, throttle: false, policy: "stop"))
      captured_model = nil
      allow_any_instance_of(Levelcode::OpenRouterAdapter).to receive(:stream) do |_a, routed, on_chunk:|
        captured_model = routed["model"]
        canned_chunks.each { |c| on_chunk.call(c) }
        Levelcode::OpenRouterAdapter::Result.new(usage: final_usage, model: "openai/gpt-oss-120b")
      end

      # A free user asking for the flagship must NOT get it.
      post "/api/levelcode/v1/ai/chat",
           params: { model: "moonshotai/kimi-k2.7-code", stream: true, messages: [ { role: "user", content: "hi" } ] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(captured_model).to eq("openai/gpt-oss-120b")
    end

    it "clamps free-tier output to FREE_MAX_TOKENS (concurrent-overshoot throttle)" do
      allow(Levelcode::Metering).to receive(:check!)
        .and_return(Levelcode::Metering::Decision.new(allowed: true, throttle: false, policy: "stop"))
      captured = nil
      allow_any_instance_of(Levelcode::OpenRouterAdapter).to receive(:stream) do |_a, routed, on_chunk:|
        captured = routed
        canned_chunks.each { |c| on_chunk.call(c) }
        Levelcode::OpenRouterAdapter::Result.new(usage: final_usage, model: "openai/gpt-oss-120b")
      end

      post "/api/levelcode/v1/ai/chat",
           params: { model: "x", stream: true, max_tokens: 999_999, messages: [ { role: "user", content: "hi" } ] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(captured["max_tokens"]).to eq(Levelcode::FREE_MAX_TOKENS)
    end

    it "402s cap_reached with an upgrade_url when the free monthly cap is hit" do
      allow(Levelcode::Metering).to receive(:check!)
        .and_return(Levelcode::Metering::Decision.new(allowed: false, throttle: false, policy: "stop"))

      post "/api/levelcode/v1/ai/chat", params: { model: "x", stream: true, messages: [] }, as: :json

      expect(response).to have_http_status(:payment_required)
      json = JSON.parse(response.body)
      expect(json.dig("error", "code")).to eq("cap_reached")
      expect(json.dig("error", "upgrade_url")).to include("/ai/pricing")
    end
  end

  describe "POST /api/levelcode/v1/ai/chat on a PAID plan (may pick either engine)" do
    # The default before-block stubs FreeTier.wallet_for -> the paid `wallet` (plan_key orbits_pro).
    before do
      allow(Levelcode::Metering).to receive(:check!)
        .and_return(Levelcode::Metering::Decision.new(allowed: true, throttle: false, policy: "throttle"))
    end

    def capture_routed_model(response_model)
      captured = nil
      allow_any_instance_of(Levelcode::OpenRouterAdapter).to receive(:stream) do |_a, routed, on_chunk:|
        captured = routed["model"]
        canned_chunks.each { |c| on_chunk.call(c) }
        Levelcode::OpenRouterAdapter::Result.new(usage: final_usage, model: response_model)
      end
      -> { captured }
    end

    it "HONORS a paid user's request for gpt-oss-120b (not just the flagship)" do
      captured = capture_routed_model("openai/gpt-oss-120b")
      post "/api/levelcode/v1/ai/chat",
           params: { model: "openai/gpt-oss-120b", stream: true, messages: [ { role: "user", content: "hi" } ] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(captured.call).to eq("openai/gpt-oss-120b")
    end

    it "defaults a paid user to the flagship for an un-entitled/unknown requested model" do
      captured = capture_routed_model("moonshotai/kimi-k2.7-code")
      post "/api/levelcode/v1/ai/chat",
           params: { model: "gpt-4o", stream: true, messages: [ { role: "user", content: "hi" } ] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(captured.call).to eq("moonshotai/kimi-k2.7-code")
    end

    it "clamps a PAID request's output to PAID_MAX_TOKENS (per-request overshoot guard)" do
      captured = nil
      allow_any_instance_of(Levelcode::OpenRouterAdapter).to receive(:stream) do |_a, routed, on_chunk:|
        captured = routed["max_tokens"]
        canned_chunks.each { |c| on_chunk.call(c) }
        Levelcode::OpenRouterAdapter::Result.new(usage: final_usage, model: "moonshotai/kimi-k2.7-code")
      end

      post "/api/levelcode/v1/ai/chat",
           params: { model: "moonshotai/kimi-k2.7-code", stream: true, max_tokens: 999_999, messages: [ { role: "user", content: "hi" } ] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(captured).to eq(Levelcode::PAID_MAX_TOKENS)
    end

    it "routes model=auto — a trivial turn goes to the cheap engine" do
      captured = capture_routed_model("openai/gpt-oss-120b")
      post "/api/levelcode/v1/ai/chat",
           params: { model: "auto", stream: true, messages: [ { role: "user", content: "hi" } ] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(captured.call).to eq("openai/gpt-oss-120b")
    end

    it "routes model=auto — a tool/agent turn goes to the flagship" do
      captured = capture_routed_model("moonshotai/kimi-k2.7-code")
      post "/api/levelcode/v1/ai/chat",
           params: { model: "auto", stream: true, tools: [ { type: "function", function: { name: "read" } } ],
                     messages: [ { role: "user", content: "refactor this" } ] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(captured.call).to eq("moonshotai/kimi-k2.7-code")
    end
  end

  describe "POST /api/levelcode/v1/ai/chat (non-stream)" do
    let(:body) { { model: "moonshotai/kimi-k2.6", stream: false, messages: [ { role: "user", content: "hi" } ] } }
    let(:upstream_json) { { "id" => "x", "choices" => [ { "message" => { "content" => "Hi" } } ], "usage" => final_usage, "model" => "moonshotai/kimi-k2.6" } }

    it "passes the upstream JSON through and meters" do
      allow(Levelcode::Metering).to receive(:check!)
        .and_return(Levelcode::Metering::Decision.new(allowed: true, throttle: false, policy: "throttle"))
      allow_any_instance_of(Levelcode::OpenRouterAdapter).to receive(:complete).and_return(upstream_json)
      expect(Levelcode::Metering).to receive(:record).with(wallet, 12, 8, 1_000)

      post "/api/levelcode/v1/ai/chat", params: body, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(upstream_json)
    end
  end
end

RSpec.describe Levelcode::Metering do
  let(:wallet) do
    instance_double(
      "CreditWallet", user_id: 42, budget_micros: 1_000_000, spent_micros: 0,
      period_start: Time.at(0), period_end: Time.at(1000), overage_policy: "throttle"
    )
  end

  describe ".check! (M14 — enforces the DOLLAR budget)" do
    it "allows and does not throttle when under budget" do
      allow($redis).to receive(:get).and_return("500000") # spent < budget
      decision = described_class.check!(wallet)
      expect(decision.allowed).to be(true)
      expect(decision.throttle).to be(false)
    end

    it "throttles when over budget under a throttle policy" do
      allow($redis).to receive(:get).and_return("1200000") # spent >= budget
      decision = described_class.check!(wallet)
      expect(decision.allowed).to be(true)
      expect(decision.throttle).to be(true)
    end

    it "blocks a zero-budget (no-plan / BYOK) wallet without touching Redis" do
      decision = described_class.check!(instance_double("CreditWallet", budget_micros: 0))
      expect(decision.allowed).to be(false)
    end

    it "degrades gracefully when Redis errors — an UNDER-budget wallet still passes" do
      allow($redis).to receive(:get).and_raise(StandardError, "down")
      decision = described_class.check!(wallet) # durable spent_micros 0 → under budget
      expect(decision.allowed).to be(true)
    end

    it "on a Redis error falls back to the DURABLE spend and still BLOCKS an over-budget hard-stop wallet" do
      over = instance_double(
        "CreditWallet", user_id: 7, budget_micros: 1_000_000, spent_micros: 1_000_000,
        period_start: Time.at(0), period_end: Time.at(1000), overage_policy: "stop"
      )
      allow($redis).to receive(:get).and_raise(StandardError, "down")
      decision = described_class.check!(over)
      expect(decision.allowed).to be(false) # durable spent == budget → hard stop survives the outage
    end

    it "enforces on the MAX of the Redis counter and durable spend — an UNDERCOUNTING Redis can't refund" do
      over = instance_double(
        "CreditWallet", user_id: 9, budget_micros: 1_000_000, spent_micros: 1_500_000,
        period_start: Time.at(0), period_end: Time.at(2000), overage_policy: "stop"
      )
      allow($redis).to receive(:get).and_return("100000") # Redis undercounts (outage/eviction/period shift)
      decision = described_class.check!(over)
      expect(decision.allowed).to be(false) # max(100k, durable 1.5M) ≥ budget → still blocked
    end

    it "treats a MISSING Redis key (period re-anchor / eviction → nil) as the durable spend, not zero" do
      over = instance_double(
        "CreditWallet", user_id: 10, budget_micros: 1_000_000, spent_micros: 1_200_000,
        period_start: Time.at(0), period_end: Time.at(3000), overage_policy: "stop"
      )
      allow($redis).to receive(:get).and_return(nil) # key miss → would be 0 without the max()
      decision = described_class.check!(over)
      expect(decision.allowed).to be(false) # max(0, durable 1.2M) → blocked (no mid-period refund)
    end
  end

  describe ".record" do
    it "increments the in/out token AND the $ spend hot counters" do
      pipe = double("pipe")
      expect(pipe).to receive(:incrby).with("levelcode:used:42:1000:in", 12)
      expect(pipe).to receive(:incrby).with("levelcode:used:42:1000:out", 8)
      expect(pipe).to receive(:incrby).with("levelcode:used:42:1000:spent", 1_000)
      allow(pipe).to receive(:expire) # TTL refresh on each write — value asserted elsewhere
      allow($redis).to receive(:pipelined).and_yield(pipe)

      expect(described_class.record(wallet, 12, 8, 1_000)).to be(true)
    end
  end
end
