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
      # Every Pro-tier engine is confirmed now — the frontier rows (Codex 5.3, GPT-5.5, Sonnet 5) went live.
      expect(Levelcode.allowed_models('orbits_pro')).to match_array([ Levelcode::DEFAULT_MODEL, Levelcode::FREE_MODEL, 'anthropic/claude-opus-4-8', 'anthropic/claude-opus-5', 'moonshotai/kimi-k3', 'openai/gpt-5.3-codex', 'openai/gpt-5.5', 'anthropic/claude-sonnet-5' ])
      # Fable 5 is confirmed too, but Max-tier — a Pro plan still can't reach it (entitlement, not price).
      expect(Levelcode.allowed_models('orbits_pro')).not_to include('anthropic/claude-fable-5', 'openai/gpt-6-astra')
    end

    it 'Pro+ reaches GPT-6 Astra; Fable stays Max-tier; Max reaches both' do
      expect(Levelcode.allowed_models('orbits_pro_plus')).to include('openai/gpt-6-astra')
      expect(Levelcode.allowed_models('orbits_pro_plus')).not_to include('anthropic/claude-fable-5')
      expect(Levelcode.allowed_models('orbits_max')).to include('openai/gpt-6-astra', 'anthropic/claude-fable-5')
      # Entitlement, not price: a Pro user asking for Astra is routed to the plan default, never 402'd.
      expect(Levelcode.gateway_model('orbits_pro', 'openai/gpt-6-astra')).to eq(Levelcode::DEFAULT_MODEL)
      expect(Levelcode.gateway_model('orbits_pro_plus', 'openai/gpt-6-astra')).to eq('openai/gpt-6-astra')
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

  describe '.estimate_cost_micros (admission-time reservation)' do
    # The input estimate is clamped DOWN to the model's context window, so the window is a ceiling on
    # what the guard will reserve. A STALE (too small) window therefore under-reserves — it waves
    # through a long-context turn that can cost several times the amount set aside for it. This is why
    # Opus 4.8's window was corrected 200K → 1M; the assertion below fails against the old value.
    it 'reserves against the real context window, so a long request cannot under-reserve' do
      long = { 'messages' => [ { 'role' => 'user', 'content' => 'x' * 2_400_000 } ] }  # ~600k tokens
      reserved = Levelcode.estimate_cost_micros('anthropic/claude-opus-4-8', long)

      # 600k input is well inside a 1M window, so the estimate must reflect all of it — not the 200k
      # the old row would have clamped it to.
      clamped_at_200k = Levelcode.cost_micros('anthropic/claude-opus-4-8', 200_000, Levelcode::PAID_MAX_TOKENS, 0)
      expect(reserved).to be > clamped_at_200k

      # And it is still bounded: a body far beyond the window clamps to the window, never past it.
      absurd = { 'messages' => [ { 'role' => 'user', 'content' => 'x' * 40_000_000 } ] }  # ~10M tokens
      ceiling = Levelcode.cost_micros('anthropic/claude-opus-4-8', 1_000_000, Levelcode::PAID_MAX_TOKENS, 0)
      expect(Levelcode.estimate_cost_micros('anthropic/claude-opus-4-8', absurd)).to eq(ceiling)
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
      # rate. Conservative fallback = the max confirmed rate. Now that Fable 5 is confirmed, the max input
      # rate is 10.0 (Fable, up from Opus's 5.0): 1M * 10.0 * 1.055 = 10_550_000.
      expect(Levelcode.cost_micros('some/unknown-model', 1_000_000, 0, 0)).to eq(10_550_000)
    end

    it 'bills the free-tier engine at its own (much cheaper) rate (incl. routing fee)' do
      # (1M * 0.03 + 1M * 0.15) * 1.055 = 180_000 * 1.055 = 189_900
      expect(Levelcode.cost_micros(Levelcode::FREE_MODEL, 1_000_000, 1_000_000, 0))
        .to eq(189_900)
    end
  end
end
