require "rails_helper"

# Web access for the editor's agent (levelcode docs/WEB-SEARCH.md): POST /ai/web/search and /ai/web/fetch.
# The search provider and the page reader are replaced at their seams (WebSearch.provider, WebFetch.get), and
# metering is stubbed at its interface as in ai_spec.rb, so these run without Redis or the network.
RSpec.describe "Api::Levelcode::V1::AiWeb", type: :request do
  let(:user) { create(:user) }
  let(:wallet) do
    instance_double("CreditWallet", user_id: user.id, plan_key: "orbits_pro", period_end: Time.current.end_of_month, overage_policy: "throttle")
  end
  let(:scope) { "ai:chat ai:agent account:read" }

  # A provider that answers from a table: a String result is an error for that query.
  let(:table) { {} }
  let(:provider) do
    t = table
    Class.new do
      define_method(:name) { "brave" }
      define_method(:search) do |q, count:, recency:|
        r = t.fetch(q, [])
        raise r if r.is_a?(String)

        r
      end
    end.new
  end

  before do
    allow_any_instance_of(Api::Levelcode::V1::AiWebController).to receive(:authenticate_levelcode!).and_return(true)
    allow_any_instance_of(Api::Levelcode::V1::AiWebController).to receive(:current_levelcode_user).and_return(user)
    allow_any_instance_of(Api::Levelcode::V1::AiWebController).to receive(:levelcode_token_claims) { { "scope" => scope } }
    allow(Levelcode::FreeTier).to receive(:wallet_for).with(user).and_return(wallet)
    allow(Levelcode::Metering).to receive(:check!).and_return(Levelcode::Metering::Decision.new(allowed: true, throttle: false, policy: "stop"))
    allow(Levelcode::Metering).to receive(:reserve!) { |_w, amount| Levelcode::Metering::Reservation.new(ok: true, amount: amount) }
    allow(Levelcode::Metering).to receive(:settle!).and_return(true)
    allow(Levelcode::Metering).to receive(:tranche_state).and_return({ remaining_micros: 7_000_000 })
    allow(Levelcode::WebSearch).to receive(:provider).and_return(provider)
    allow(Levelcode::WebSearch).to receive(:cost_micros_per_query).and_return(5_000)
    allow(RecordUsageJob).to receive(:perform_async)
  end

  def search(body)
    post "/api/levelcode/v1/ai/web/search", params: body, as: :json
  end

  describe "POST /ai/web/search" do
    let(:table) do
      { "csaf" => [ { title: "CSAF 2.1", url: "https://docs.oasis-open.org/csaf/", snippet: "spec", date: "" } ],
        "openeox" => [ { title: "OpenEoX", url: "https://openeox.org/", snippet: "eol", date: "2026-03-01" } ],
        "broken" => "Brave Search answered HTTP 429" }
    end

    it "answers every query, in order, with the results and the credits object the chat stream ends with" do
      search(queries: [ "csaf", "openeox" ], count: 3)

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["results"].map { |r| r["query"] }).to eq(%w[csaf openeox])
      expect(json["results"][0]["results"][0]).to include("title" => "CSAF 2.1", "url" => "https://docs.oasis-open.org/csaf/")
      expect(json["levelcode"]).to eq(
        "cost_micros" => Levelcode.retail_micros(10_000, "orbits_pro"),
        "credits_remaining_micros" => Levelcode.retail_micros(7_000_000, "orbits_pro")
      )
    end

    it "reserves the worst case, then settles and records only the queries that answered — one ledger row" do
      search(queries: [ "csaf", "broken" ])

      expect(Levelcode::Metering).to have_received(:reserve!).with(wallet, 10_000)
      expect(Levelcode::Metering).to have_received(:settle!).with(wallet, 10_000, 0, 0, 5_000).once
      expect(RecordUsageJob).to have_received(:perform_async)
        .with(user.id, kind_of(String), "web-search", "brave", 0, 0, 0, 5_000, wallet.period_end.to_i, kind_of(Integer)).once
      expect(response.parsed_body["results"][1]).to eq("query" => "broken", "results" => [], "error" => "Brave Search answered HTTP 429")
    end

    it "bills nothing and writes no ledger row when no query answered" do
      search(queries: [ "broken" ])

      expect(Levelcode::Metering).to have_received(:settle!).with(wallet, 5_000, 0, 0, 0).once
      expect(RecordUsageJob).not_to have_received(:perform_async)
    end

    it "cleans the queries: trimmed, duplicates dropped, at most four" do
      seen = []
      allow(provider).to receive(:search) { |q, **| seen << q; [] }
      search(queries: [ "  a  b ", "A B", "c", "", "d", "e", "f" ])

      expect(seen).to match_array([ "a b", "c", "d", "e" ])
      expect(Levelcode::Metering).to have_received(:reserve!).with(wallet, 20_000)
    end

    it "passes count (clamped) and a known recency to the provider, and ignores an unknown one" do
      calls = []
      allow(provider).to receive(:search) { |q, count:, recency:| calls << [ q, count, recency ]; [] }
      search(queries: [ "x" ], count: 99, recency: "week")
      search(queries: [ "y" ], recency: "decade")

      expect(calls).to eq([ [ "x", 10, "week" ], [ "y", Levelcode::WebSearch::DEFAULT_COUNT, nil ] ])
    end

    it "422s without a query, and 503s — billing nothing — when no search key is set" do
      search(queries: [ "", "  " ])
      expect(response).to have_http_status(:unprocessable_entity)

      allow(Levelcode::WebSearch).to receive(:provider).and_return(nil)
      search(queries: [ "csaf" ])
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body.dig("error", "code")).to eq("web_search_unavailable")
      expect(Levelcode::Metering).not_to have_received(:reserve!)
    end

    it "402s when the wallet is over its cap, when a throttle plan is over budget, or when the reservation does not fit" do
      allow(Levelcode::Metering).to receive(:check!).and_return(Levelcode::Metering::Decision.new(allowed: false, throttle: false, policy: "stop"))
      search(queries: [ "csaf" ])
      expect(response).to have_http_status(:payment_required)

      allow(Levelcode::Metering).to receive(:check!).and_return(Levelcode::Metering::Decision.new(allowed: true, throttle: true, policy: "throttle"))
      search(queries: [ "csaf" ])
      expect(response).to have_http_status(:payment_required)

      allow(Levelcode::Metering).to receive(:check!).and_return(Levelcode::Metering::Decision.new(allowed: true, throttle: false, policy: "stop"))
      allow(Levelcode::Metering).to receive(:reserve!).and_return(Levelcode::Metering::Reservation.new(ok: false, amount: 0))
      search(queries: [ "csaf" ])
      expect(response).to have_http_status(:payment_required)
      expect(response.parsed_body.dig("error", "code")).to eq("cap_reached")
    end

    it "releases the reservation when the search itself blows up" do
      allow(Levelcode::WebSearch).to receive(:run).and_raise(RuntimeError, "boom")
      expect { search(queries: [ "csaf" ]) }.to raise_error(RuntimeError, "boom")
      expect(Levelcode::Metering).to have_received(:settle!).with(wallet, 5_000, 0, 0, 0).once
    end

    context "with a token that is not an agent token" do
      let(:scope) { "ai:chat account:read" }

      it "403s before anything is reserved" do
        search(queries: [ "csaf" ])
        expect(response).to have_http_status(:forbidden)
        expect(Levelcode::Metering).not_to have_received(:reserve!)
      end
    end
  end

  describe "POST /ai/web/fetch" do
    def fetch(url)
      post "/api/levelcode/v1/ai/web/fetch", params: { url: url }, as: :json
    end

    it "answers the page's text, final address and type" do
      allow(Levelcode::WebFetch).to receive(:get).with("https://openeox.org/a")
        .and_return(final_url: "https://openeox.org/b", status: 200, content_type: "text/html", body: "<p>hi</p>", truncated: false)
      fetch("https://openeox.org/a")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("final_url" => "https://openeox.org/b", "status" => 200, "content_type" => "text/html", "body" => "<p>hi</p>", "truncated" => false)
    end

    it "refuses what is not an http(s) address before reading anything" do
      allow(Levelcode::WebFetch).to receive(:get)
      [ "file:///etc/passwd", "gopher://x", "https://#{'a' * 2100}.org" ].each do |u|
        fetch(u)
        expect(response).to have_http_status(:unprocessable_entity)
      end
      expect(Levelcode::WebFetch).not_to have_received(:get)
    end

    it "says why a page was not read: blocked, not text, too slow, unreachable" do
      { Levelcode::WebFetch::Blocked.new("x is on a private or local network") => [ :unprocessable_entity, "blocked" ],
        Levelcode::WebFetch::NotText.new("application/pdf is not a text page") => [ :unsupported_media_type, "not_text" ],
        Net::ReadTimeout.new => [ :gateway_timeout, "timeout" ],
        SocketError.new("getaddrinfo") => [ :bad_gateway, "unreachable" ] }.each do |error, (status, code)|
        allow(Levelcode::WebFetch).to receive(:get).and_raise(error)
        fetch("https://example.org/")
        expect(response).to have_http_status(status)
        expect(response.parsed_body.dig("error", "code")).to eq(code)
      end
    end
  end
end
