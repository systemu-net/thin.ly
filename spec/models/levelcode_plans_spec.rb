require 'rails_helper'

RSpec.describe Levelcode do
  describe 'PLANS' do
    it 'defines the four frozen tiers in order' do
      expect(Levelcode::PLANS.map { |p| p[:key] }).to eq(
        %w[orbits_pro orbits_pro_plus orbits_max orbits_ultra]
      )
    end

    it 'matches the SPEC §6 caps and prices' do
      expected = {
        'orbits_pro'      => { price_cents: 2_000,  input_cap: 15_000_000, output_cap: 2_000_000 },
        'orbits_pro_plus' => { price_cents: 4_000,  input_cap: 35_000_000, output_cap: 4_500_000 },
        'orbits_max'      => { price_cents: 6_000,  input_cap: 55_000_000, output_cap: 7_000_000 },
        'orbits_ultra'    => { price_cents: 10_000, input_cap: 95_000_000, output_cap: 12_000_000 }
      }

      Levelcode::PLANS.each do |plan|
        e = expected[plan[:key]]
        expect(plan[:price_cents]).to eq(e[:price_cents])
        expect(plan[:input_cap]).to eq(e[:input_cap])
        expect(plan[:output_cap]).to eq(e[:output_cap])
        expect(plan[:interval]).to eq('month')
        expect(plan[:stripe_lookup_key]).to eq(plan[:key])
        expect(plan[:features]).to be_an(Array).and be_present
      end
    end
  end

  describe 'credits (the in-product spending unit)' do
    it 'converts retail micro-$ at $1 = 100 credits' do
      expect(Levelcode::CREDITS_PER_DOLLAR).to eq(100)
      expect(Levelcode::MICROS_PER_CREDIT).to eq(10_000)
      expect(Levelcode.micros_to_credits(12_790_000)).to eq(1_279.0)  # the dashboard's "$12.79 left"
      expect(Levelcode.micros_to_credits(0)).to eq(0.0)
    end

    it "gives each plan an allowance equal to its price in CENTS" do
      # Not a coincidence to be re-derived by hand anywhere: budget_micros == price × CREDIT_COGS_RATIO
      # and retail divides that ratio back out, so the credit allowance lands exactly on price_cents.
      # $100 Ultra → 10_000 credits. Pinned because the marketing copy states these numbers.
      {
        'orbits_pro' => 2_000, 'orbits_pro_plus' => 4_000,
        'orbits_max' => 6_000, 'orbits_ultra' => 10_000
      }.each do |key, credits|
        expect(Levelcode.plan_credits(key)).to eq(credits)
        expect(Levelcode.plan_credits(key)).to eq(Levelcode.plan(key)[:price_cents])
      end
    end

    it 'survives a change to the COGS ratio — the allowance still tracks the price' do
      # The allowance is revenue-derived, so moving the margin must NOT move what the customer is told
      # they get. This is the property that makes "Ultra = 10,000 credits" safe to print.
      stub_const('Levelcode::CREDIT_COGS_RATIO', 0.30)
      expect(Levelcode.plan_credits('orbits_ultra')).to eq(10_000)
    end
  end

  describe '.roster_for per-turn economics' do
    it 'reports per_turn_micros in the same RETAIL unit as the balance' do
      row = Levelcode.roster_for('orbits_pro_plus', 0).find { |m| m[:id] == 'moonshotai/kimi-k2.7-code' }
      # ~7.7 credits/turn on the 1× flagship — the figure the dashboard prints beside "≈ turns left".
      expect(Levelcode.micros_to_credits(row[:per_turn_micros])).to be_within(0.5).of(7.7)
    end

    it 'keeps per_turn_micros and turns_left in exact agreement across MANY balances' do
      # The load-bearing invariant: the dashboard prints "N credits/turn" beside "≈ turns left" and the
      # user divides one into the other by eye, so they must agree for EVERY balance, not on average.
      #
      # This test used to assert a single balance and passed while the invariant was broken — turns came
      # from COST micro-$ while the per-turn figure was ROUNDED RETAIL, so the two rounded independently
      # and disagreed for ~12% of balances (PR #380 review; measured 3,440 of 28,000 sampled). One value
      # proves nothing about a rounding boundary, so sweep a range that crosses many of them.
      plan = 'orbits_pro_plus'
      (1..400).each do |k|
        balance = k * 12_345
        retail_balance = Levelcode.retail_micros(balance, plan)
        Levelcode.roster_for(plan, balance).each do |m|
          expect(retail_balance / m[:per_turn_micros]).to eq(m[:turns_left]),
                                                         "#{m[:id]} @ #{balance}: balance ÷ per-turn " \
                                                         "(#{retail_balance / m[:per_turn_micros]}) != " \
                                                         "turns_left (#{m[:turns_left]})"
        end
      end
    end

    it 'reports whole micro-dollars for a turn, not a float' do
      # per_turn_cost_micros multiplies an integer cost by the float routing fee; leaving it a Float let
      # the imprecision leak into the turn counts. The name says micro-$ — it should BE micro-$.
      expect(Levelcode.per_turn_cost_micros('moonshotai/kimi-k2.7-code')).to be_a(Integer)
      expect(Levelcode.retail_per_turn_micros('orbits_pro_plus', 'moonshotai/kimi-k2.7-code')).to be_a(Integer)
      Levelcode.roster_for('orbits_pro_plus', 1_000_000).each do |m|
        expect(m[:per_turn_micros]).to be_a(Integer), "#{m[:id]} per_turn_micros must be an Integer"
        expect(m[:turns_left]).to be_a(Integer)
      end
    end
  end

  describe 'gross margin (the economic invariant credits must not disturb)' do
    # The business promise: model COGS stay at or below CREDIT_COGS_RATIO of subscription revenue, so
    # gross margin is (1 - ratio) — 50% today — NO MATTER which models a customer picks. That holds
    # because the budget is enforced in COST micro-$ while metering charges each model its real wire
    # price: an expensive model burns the same dollar allowance faster, it does not overspend it.
    #
    # Denominating the customer's balance in CREDITS is presentation only and must never move this. This
    # spec is the standing proof of that — if a future change to pricing, the roster, the routing fee or
    # the credit conversion ever eats the margin, it fails here rather than in a monthly P&L.
    it 'caps COGS at the target share of revenue for every plan' do
      Levelcode::PLANS.each do |plan|
        revenue = plan[:price_cents] / 100.0
        max_cogs = Levelcode.budget_micros(plan[:key]) / 1_000_000.0
        expect(max_cogs).to be <= (revenue * Levelcode::CREDIT_COGS_RATIO) + 0.005,
                            "#{plan[:name]}: enforced budget $#{max_cogs.round(2)} exceeds its COGS share"
        margin = (revenue - max_cogs) / revenue
        expect(margin).to be >= (1 - Levelcode::CREDIT_COGS_RATIO) - 0.001,
                          "#{plan[:name]}: margin #{(margin * 100).round(1)}% is under target"
      end
    end

    it 'holds for ANY model mix — the worst case is still at target' do
      # Spending the entire allowance on the single priciest model is the adversarial case: if margin
      # survives that, it survives every blend. Checked per model rather than on an average.
      Levelcode::PLANS.each do |plan|
        revenue = plan[:price_cents] / 100.0
        Levelcode.roster_for(plan[:key], Levelcode.budget_micros(plan[:key])).each do |m|
          cogs = m[:turns_left] * Levelcode.per_turn_cost_micros(m[:id]) / 1_000_000.0
          margin = (revenue - cogs) / revenue
          expect(margin).to be >= (1 - Levelcode::CREDIT_COGS_RATIO) - 0.001,
                            "#{plan[:name]} spent entirely on #{m[:id]}: margin #{(margin * 100).round(1)}%"
        end
      end
    end

    it 'keeps the credit allowance and the COGS ceiling two sides of one number' do
      # credits are retail (= price), the enforced budget is cost (= price x ratio). If those ever drift
      # apart, customers are either given credits we do not fund or funded for credits they cannot spend.
      Levelcode::PLANS.each do |plan|
        credits_in_dollars = Levelcode.plan_credits(plan[:key]) / Levelcode::CREDITS_PER_DOLLAR.to_f
        cost_budget = Levelcode.budget_micros(plan[:key]) / 1_000_000.0
        expect(cost_budget).to be_within(0.01).of(credits_in_dollars * Levelcode::CREDIT_COGS_RATIO)
      end
    end
  end

  describe '.plan' do
    it 'looks up a plan by key' do
      expect(Levelcode.plan('orbits_max')[:name]).to eq('Max')
    end

    it 'returns nil for an unknown key' do
      expect(Levelcode.plan('nope')).to be_nil
    end
  end

  describe '.allowed_models / .gateway_model (entitlement)' do
    it 'free/no-plan may use ONLY the open-weights engine' do
      expect(Levelcode.allowed_models('free')).to eq([ Levelcode::FREE_MODEL ])
      expect(Levelcode.allowed_models(nil)).to eq([ Levelcode::FREE_MODEL ])
    end

    it 'a paid plan may use the flagship AND the open-weights engine (confirmed-price roster)' do
      # Kimi K3 joined the confirmed-price roster (a selectable Pro pick — see the gateway K3 change).
      expect(Levelcode.allowed_models('orbits_pro')).to match_array([ Levelcode::DEFAULT_MODEL, Levelcode::FREE_MODEL, 'anthropic/claude-opus-4-8', 'moonshotai/kimi-k3' ])
      # A tier-entitled but ASSUMPTION-priced frontier model stays staged — never billed on a guess.
      expect(Levelcode.allowed_models('orbits_pro')).not_to include('openai/gpt-5.5')
    end

    it 'free CANNOT reach the flagship no matter what is requested' do
      expect(Levelcode.gateway_model('free', Levelcode::DEFAULT_MODEL)).to eq(Levelcode::FREE_MODEL)
      expect(Levelcode.gateway_model('free', nil)).to eq(Levelcode::FREE_MODEL)
    end

    it 'paid HONORS a requested allowed model (gpt-oss too), else defaults to the flagship' do
      expect(Levelcode.gateway_model('orbits_pro', Levelcode::FREE_MODEL)).to eq(Levelcode::FREE_MODEL)
      expect(Levelcode.gateway_model('orbits_pro', Levelcode::DEFAULT_MODEL)).to eq(Levelcode::DEFAULT_MODEL)
      expect(Levelcode.gateway_model('orbits_pro', 'some/other-model')).to eq(Levelcode::DEFAULT_MODEL)
      expect(Levelcode.gateway_model('orbits_pro', nil)).to eq(Levelcode::DEFAULT_MODEL)
    end
  end

  describe '.auto_route (the "Auto" pseudo-model — cheapest engine that fits)' do
    let(:trivial) { { "messages" => [ { "role" => "user", "content" => "hi there" } ] } }
    let(:long_content) { "x" * (Levelcode::AUTO_TRIVIAL_CHARS + 1) }
    let(:heavy) { { "messages" => [ { "role" => "user", "content" => long_content } ] } }
    let(:with_tools) { trivial.merge("tools" => [ { "type" => "function", "function" => { "name" => "read" } } ]) }

    it 'routes a trivial (short, tool-less) turn to the cheap open-weights engine' do
      expect(Levelcode.auto_route('orbits_pro', trivial)).to eq(Levelcode::FREE_MODEL)
    end

    it 'routes a large-input turn to the plan default (flagship on paid)' do
      expect(Levelcode.auto_route('orbits_pro', heavy)).to eq(Levelcode::DEFAULT_MODEL)
    end

    it 'routes ANY tool/agent turn to the plan default (tools need the strong model)' do
      expect(Levelcode.auto_route('orbits_pro', with_tools)).to eq(Levelcode::DEFAULT_MODEL)
    end

    it 'never over-reaches a free plan — both branches land on the open-weights engine' do
      expect(Levelcode.auto_route('free', trivial)).to eq(Levelcode::FREE_MODEL)
      expect(Levelcode.auto_route('free', heavy)).to eq(Levelcode::FREE_MODEL)
      expect(Levelcode.auto_route('free', with_tools)).to eq(Levelcode::FREE_MODEL)
    end

    it 'tolerates a missing/blank messages array (defaults to the cheap engine)' do
      expect(Levelcode.auto_route('orbits_pro', {})).to eq(Levelcode::FREE_MODEL)
      expect(Levelcode.auto_route('orbits_pro', { "messages" => nil })).to eq(Levelcode::FREE_MODEL)
    end

    # Malformed, CLIENT-CONTROLLED bodies must never 500 the gateway (D56 adversarial review — 4
    # confirmed crash variants). The transparent proxy does no message-shape validation.
    it 'never raises on a malformed messages payload (nil/scalar element, bare object)' do
      expect { Levelcode.auto_route('orbits_pro', { "messages" => [ nil ] }) }.not_to raise_error
      expect { Levelcode.auto_route('orbits_pro', { "messages" => [ 5 ] }) }.not_to raise_error
      expect { Levelcode.auto_route('orbits_pro', { "messages" => { "role" => "user", "content" => "hi" } }) }.not_to raise_error
      expect { Levelcode.auto_route('orbits_pro', { "messages" => "just a string" }) }.not_to raise_error
      # A trailing null turn appended after a real one → skip the junk, still measure the real content.
      expect(Levelcode.auto_route('orbits_pro', { "messages" => [ { "role" => "user", "content" => "hi" }, nil ] })).to eq(Levelcode::FREE_MODEL)
    end

    it 'measures a single bare-object message by its content (routes trivial → cheap)' do
      expect(Levelcode.auto_route('orbits_pro', { "messages" => { "role" => "user", "content" => "hi" } })).to eq(Levelcode::FREE_MODEL)
      expect(Levelcode.auto_route('orbits_pro', { "messages" => { "role" => "user", "content" => long_content } })).to eq(Levelcode::DEFAULT_MODEL)
    end

    it 'routes a multimodal (image) turn to the strong model regardless of text length' do
      vision = { "messages" => [ { "role" => "user", "content" => [
        { "type" => "text", "text" => "what is this?" },
        { "type" => "image_url", "image_url" => { "url" => "data:image/png;base64,AAAA" } }
      ] } ] }
      expect(Levelcode.auto_route('orbits_pro', vision)).to eq(Levelcode::DEFAULT_MODEL)
    end

    it 'measures a text-only multimodal parts array by its text (short → cheap)' do
      text_parts = { "messages" => [ { "role" => "user", "content" => [ { "type" => "text", "text" => "hi" } ] } ] }
      expect(Levelcode.auto_route('orbits_pro', text_parts)).to eq(Levelcode::FREE_MODEL)
    end

    it 'the routed target is always allowed on the plan (never over-reaches entitlement)' do
      [ trivial, heavy, with_tools ].each do |body|
        model = Levelcode.auto_route('orbits_pro', body)
        expect(Levelcode.allowed_models('orbits_pro')).to include(model)
      end
    end
  end

  describe '.rate_table' do
    it 'uses the SPEC §1.1 per-token micro rates for the default model' do
      rate = Levelcode.rate_table[Levelcode::DEFAULT_MODEL]
      expect(rate[:input]).to eq(0.74)
      expect(rate[:cached_input]).to eq(0.15)
      expect(rate[:output]).to eq(3.50)
    end

    it 'prices the free-tier engine (gpt-oss-120b) well below the flagship' do
      free = Levelcode.rate_table[Levelcode::FREE_MODEL]
      expect(free[:input]).to eq(0.03)
      expect(free[:output]).to eq(0.15)
      expect(free[:input]).to be < Levelcode.rate_table[Levelcode::DEFAULT_MODEL][:input]
    end
  end

  describe '.cost_micros' do
    # Every charge includes the OpenRouter routing fee (× ROUTING_FEE) so the ledger meters the true
    # wire cost and the target margin holds. Base list-price figures below, then × 1.055.
    it 'bills uncached input, cached input, and output at their rates (incl. routing fee)' do
      # 1M input (all uncached) + 1M output on the default model:
      # (1_000_000 * 0.74 + 1_000_000 * 3.50) * 1.055 = 4_240_000 * 1.055 = 4_473_200
      expect(Levelcode.cost_micros(Levelcode::DEFAULT_MODEL, 1_000_000, 1_000_000, 0))
        .to eq(4_473_200)
    end

    it 'bills the cached subset at the cheaper cached rate (incl. routing fee)' do
      # (400_000 * 0.74 + 600_000 * 0.15) * 1.055 = 386_000 * 1.055 = 407_230
      expect(Levelcode.cost_micros(Levelcode::DEFAULT_MODEL, 1_000_000, 0, 600_000))
        .to eq(407_230)
    end

    it 'clamps cached tokens to the input count' do
      # cached > input → fully cached: (1000 * 0.15) * 1.055 = 150 * 1.055 = 158.25 → 158
      expect(Levelcode.cost_micros(Levelcode::DEFAULT_MODEL, 1_000, 0, 5_000)).to eq(158)
    end

    it 'falls back to the MOST EXPENSIVE confirmed rate for unknown/off-catalog models (never under-bills)' do
      # An off-catalog id (e.g. a dated snapshot or upstream substitution) must not bill at the cheapest
      # rate. Conservative fallback = the max confirmed rate (Opus input 5.0): 1M * 5.0 * 1.055 = 5_275_000
      expect(Levelcode.cost_micros('some/unknown-model', 1_000_000, 0, 0)).to eq(5_275_000)
    end

    it 'bills the free-tier engine at its own (much cheaper) rate (incl. routing fee)' do
      # (1M * 0.03 + 1M * 0.15) * 1.055 = 180_000 * 1.055 = 189_900
      expect(Levelcode.cost_micros(Levelcode::FREE_MODEL, 1_000_000, 1_000_000, 0))
        .to eq(189_900)
    end
  end
end
