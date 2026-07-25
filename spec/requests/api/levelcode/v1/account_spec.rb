require "rails_helper"

RSpec.describe "Api::Levelcode::V1::Account", type: :request do
  PROFILE_URL = "/api/levelcode/v1/account/profile"
  USAGE_URL   = "/api/levelcode/v1/account/usage"

  let(:user) { create(:user, stripe_id: "cus_test123") }

  before do
    allow(Stripe::Customer).to receive(:create).and_return(double(id: "cus_test123"))
    allow_any_instance_of(Api::Levelcode::V1::BaseController).to receive(:authenticate_levelcode!).and_return(true)
    allow_any_instance_of(Api::Levelcode::V1::BaseController).to receive(:current_user).and_return(user)
    allow(user).to receive(:role).and_return("member")
  end

  describe "GET /api/levelcode/v1/account/activity" do
    it "returns per-day counts, a per-model breakdown, and totals from the ledger" do
      UsageEvent.create!(user: user, model: "openai/gpt-oss-120b", provider: "openrouter",
                         input_tokens: 100, output_tokens: 50, cost_micros: 10, created_at: Time.zone.local(2026, 3, 4, 12))
      UsageEvent.create!(user: user, model: "moonshotai/kimi-k2.7-code", provider: "openrouter",
                         input_tokens: 200, output_tokens: 80, cost_micros: 40, created_at: Time.zone.local(2026, 3, 4, 15))
      UsageEvent.create!(user: user, model: "openai/gpt-oss-120b", provider: "openrouter",
                         input_tokens: 10, output_tokens: 5, cost_micros: 1, created_at: Time.zone.local(2025, 1, 1, 9)) # other year
      UsageFeedback.create!(user: user, model: "openai/gpt-oss-120b", rating: "up", created_at: Time.zone.local(2026, 3, 4, 12))

      get "/api/levelcode/v1/account/activity", params: { year: 2026 }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["year"]).to eq(2026)
      expect(body["total"]).to eq(2)                       # only the two 2026 events
      expect(body.dig("days", "2026-03-04", "count")).to eq(2)
      expect(body["days"]).not_to have_key("2025-01-01")   # scoped to the requested year
      gpt = body["models"].find { |m| m["model"] == "openai/gpt-oss-120b" }
      expect(gpt["count"]).to eq(1)
      expect(gpt["up"]).to eq(1)
      expect(body["years"]).to include(2026, 2025)
    end

    it "reports the user's spend at RETAIL, matching the balance shown on the same page" do
      # The ledger stores what a request cost us at the wire. Reporting that raw understated what the
      # customer actually spent (by the margin) and put two units on one page — a retail balance above,
      # cost-denominated per-model rows below. Both must now be the same unit, or the per-model figures
      # cannot be reconciled against the credits the dashboard says were spent.
      CreditWallet.create!(user: user, product: "levelcode", plan_key: "orbits_pro",
                           input_cap: 15_000_000, output_cap: 2_000_000,
                           budget_micros: Levelcode.budget_micros("orbits_pro"), spent_micros: 0,
                           period_start: Time.current, period_end: 1.month.from_now, overage_policy: "throttle")
      UsageEvent.create!(user: user, model: "moonshotai/kimi-k2.7-code", provider: "openrouter",
                         input_tokens: 100, output_tokens: 50, cost_micros: 1_000,
                         created_at: Time.zone.local(2026, 5, 2, 10))

      get "/api/levelcode/v1/account/activity", params: { year: 2026 }

      expect(response).to have_http_status(:ok)
      expected = Levelcode.retail_micros(1_000, "orbits_pro")
      expect(expected).to be > 1_000, "precondition: retail must exceed cost, or this proves nothing"
      kimi = response.parsed_body["models"].find { |m| m["model"] == "moonshotai/kimi-k2.7-code" }
      expect(kimi["cost_micros"]).to eq(expected)
      expect(response.parsed_body.dig("days", "2026-05-02", "cost_micros")).to eq(expected)
      day_model = response.parsed_body.dig("days", "2026-05-02", "models").first
      expect(day_model["cost_micros"]).to eq(expected), "the per-day model rows must convert too"
    end

    it "leaves costs at raw COST when no plan_key is given (the operator's view)" do
      # Levelcode::Activity is a shared service. An operator-side caller wants real COGS, not what the
      # customer was charged — so the conversion is opt-in rather than baked into the aggregation.
      UsageEvent.create!(user: user, model: "openai/gpt-oss-120b", provider: "openrouter",
                         input_tokens: 10, output_tokens: 5, cost_micros: 777,
                         created_at: Time.zone.local(2026, 6, 1, 10))
      raw = Levelcode::Activity.for_user(user, year: 2026)
      expect(raw[:models].find { |m| m[:model] == "openai/gpt-oss-120b" }[:cost_micros]).to eq(777)
    end

    it "merges a dated model snapshot with feedback recorded against the base model id" do
      # Metering records the upstream-resolved snapshot; the editor records feedback against the
      # requested base id. They must aggregate to ONE per-model row (the reported bug).
      UsageEvent.create!(user: user, model: "moonshotai/kimi-k2.7-code-20260612", provider: "openrouter",
                         input_tokens: 100, output_tokens: 50, cost_micros: 10, created_at: Time.zone.local(2026, 4, 1, 10))
      UsageFeedback.create!(user: user, model: "moonshotai/kimi-k2.7-code", rating: "up", created_at: Time.zone.local(2026, 4, 1, 10))
      UsageFeedback.create!(user: user, model: "moonshotai/kimi-k2.7-code", rating: "down", created_at: Time.zone.local(2026, 4, 1, 11))

      get "/api/levelcode/v1/account/activity", params: { year: 2026 }

      expect(response).to have_http_status(:ok)
      kimi = response.parsed_body["models"].find { |m| m["model"] == "moonshotai/kimi-k2.7-code" }
      expect(kimi).to be_present
      expect(kimi["count"]).to eq(1)  # the dated usage_event
      expect(kimi["up"]).to eq(1)     # feedback on the base id joins the dated snapshot
      expect(kimi["down"]).to eq(1)
    end
  end

  describe "GET /api/levelcode/v1/account/models" do
    it "returns the entitled roster with multipliers, turns-left, and a live flag" do
      CreditWallet.create!(user: user, product: "levelcode", plan_key: "orbits_pro",
                           input_cap: 15_000_000, output_cap: 2_000_000,
                           budget_micros: Levelcode.budget_micros("orbits_pro"), spent_micros: 0,
                           period_start: Time.current, period_end: 1.month.from_now, overage_policy: "throttle")
      allow(Levelcode::Metering).to receive(:spent_micros).and_return(0)

      get "/api/levelcode/v1/account/models"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["plan"]).to eq("Pro")
      ids = body["models"].map { |m| m["id"] }
      expect(ids).to include("openai/gpt-oss-120b", "moonshotai/kimi-k2.7-code", "moonshotai/kimi-k3", "anthropic/claude-opus-4-8", "anthropic/claude-opus-5")
      kimi = body["models"].find { |m| m["id"] == "moonshotai/kimi-k2.7-code" }
      expect(kimi["live"]).to be(true)
      expect(kimi["multiplier"]).to eq(1.0)
      expect(kimi["turns_left"]).to be_within(2).of(260)  # $10 budget (50% of $20) ÷ Kimi ref-turn
      k3 = body["models"].find { |m| m["id"] == "moonshotai/kimi-k3" }
      expect(k3["live"]).to be(true)                   # confirmed OpenRouter price → selectable + billable
      expect(k3["multiplier"]).to be_within(0.05).of(4.00)   # ~4× the Kimi K2.7 flagship baseline
      opus = body["models"].find { |m| m["id"] == "anthropic/claude-opus-4-8" }
      expect(opus["live"]).to be(true)                # price confirmed → live + billable
      expect(opus["multiplier"]).to be_within(0.05).of(6.67)
      # Opus 5 rides the same price sheet, so Pro sees it at the SAME multiplier as 4.8 — the newer
      # model costs a Pro user no more per turn. `live` is the bit that matters: an :assumption-priced
      # row would render in the picker but silently fall back to the plan default when selected.
      opus5 = body["models"].find { |m| m["id"] == "anthropic/claude-opus-5" }
      expect(opus5["live"]).to be(true)
      expect(opus5["multiplier"]).to be_within(0.05).of(6.67)

      # Per-turn cost rides along in the SAME retail unit as the balance fields, so the dashboard can
      # render "N credits/turn" beside "≈ turns left" using one conversion. ~7.7 credits on the 1×
      # flagship; Opus is ~6.67× that.
      expect(kimi["per_turn_micros"]).to be > 0
      expect(Levelcode.micros_to_credits(kimi["per_turn_micros"])).to be_within(0.5).of(7.7)
      expect(opus["per_turn_micros"]).to be > kimi["per_turn_micros"]
    end
  end

  describe "GET /api/levelcode/v1/account/profile" do
    it "returns the SPEC §3 profile shape" do
      get PROFILE_URL

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.keys).to include("id", "email", "name", "plan", "role")
      expect(body["id"]).to eq(user.id)
      expect(body["email"]).to eq(user.email)
      expect(body["role"]).to eq("member")
    end
  end

  describe "GET /api/levelcode/v1/account/usage" do
    context "when the user has a provisioned wallet" do
      let!(:wallet) do
        CreditWallet.create!(
          user: user,
          product: "levelcode",
          plan_key: "orbits_pro",
          input_cap: 15_000_000,
          output_cap: 2_000_000,
          budget_micros: Levelcode.budget_micros("orbits_pro"), # M14: the enforced DOLLAR allowance
          spent_micros: 5_000_000,
          input_used: 1_234,
          output_used: 567,
          period_start: Time.current,
          period_end: 1.month.from_now,
          overage_policy: "throttle"
        )
      end

      it "returns the plan, dollar budget/spend, and token usage from the CreditWallet" do
        allow(Levelcode::Metering).to receive(:spent_micros).and_return(5_000_000) # live spend (Redis path stubbed)
        get USAGE_URL

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["plan"]).to eq("Pro") # friendly Levelcode name, not the raw "orbits_pro" key
        # Retail credits: the API shows what the user PAID — the $20 price — not the $10 cost budget.
        expect(body["budget_micros"]).to eq(20_000_000)
        expect(body["budget_micros"]).to eq(Levelcode.retail_micros(Levelcode.budget_micros("orbits_pro"), "orbits_pro"))
        expect(body["spent_micros"]).to eq(Levelcode.retail_micros(5_000_000, "orbits_pro"))
        expect(body["credits_remaining_micros"]).to eq(Levelcode.retail_micros(Levelcode.budget_micros("orbits_pro") - 5_000_000, "orbits_pro"))
        expect(body["input_used"]).to eq(1_234)
        expect(body["input_cap"]).to eq(15_000_000)
        expect(body["output_used"]).to eq(567)
        expect(body["output_cap"]).to eq(2_000_000)
        expect(body["overage_policy"]).to eq("throttle")
        expect(body).to have_key("period_end")
      end
    end

    context "with rolling usage windows active (LEVELCODE_BUDGET_TRANCHES=3)" do
      let!(:wallet) do
        CreditWallet.create!(
          user: user, product: "levelcode", plan_key: "orbits_pro",
          input_cap: 15_000_000, output_cap: 2_000_000,
          budget_micros: Levelcode.budget_micros("orbits_pro"), spent_micros: 0,
          period_start: Time.current, period_end: 1.month.from_now, overage_policy: "throttle"
        )
      end

      it "reports remaining against the UNLOCKED ceiling (budget/3), not the full budget, with an unlock date" do
        stub_const("Levelcode::BUDGET_TRANCHES", 3)
        allow(Levelcode::Metering).to receive(:spent_micros).and_return(0)
        full = Levelcode.budget_micros("orbits_pro")

        get USAGE_URL

        body = response.parsed_body
        expect(body["budget_micros"]).to eq(Levelcode.retail_micros(full, "orbits_pro"))          # full allowance, retail
        expect(body["ceiling_micros"]).to eq(Levelcode.retail_micros(full / 3, "orbits_pro"))     # only the first tranche is unlocked
        expect(body["credits_remaining_micros"]).to eq(Levelcode.retail_micros(full / 3, "orbits_pro")) # vs the ceiling, NOT the full budget
        expect(body["next_unlock_at"]).to be_present              # and we say when more unlocks
      end
    end

    context "when the user has no wallet yet (M11 free tier)" do
      it "provisions the free tier — gpt-oss engine, free caps, hard-cap policy" do
        get USAGE_URL

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["plan"]).to eq("Free")
        expect(body["model"]).to eq(Levelcode::FREE_MODEL)
        expect(body["input_used"]).to eq(0)
        expect(body["input_cap"]).to eq(Levelcode::FREE_INPUT_CAP)
        expect(body["output_cap"]).to eq(Levelcode::FREE_OUTPUT_CAP)
        expect(body["overage_policy"]).to eq("stop")
      end
    end
  end
end
