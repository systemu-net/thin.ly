require "rails_helper"

RSpec.describe Levelcode::WebSearch do
  describe ".provider" do
    around do |ex|
      saved = ENV.to_h.slice("LEVELCODE_WEB_SEARCH_PROVIDER", "BRAVE_SEARCH_API_KEY")
      ex.run
    ensure
      %w[LEVELCODE_WEB_SEARCH_PROVIDER BRAVE_SEARCH_API_KEY].each { |k| saved.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
    end

    it "is Brave when its key is set, and nil (search unavailable) without one or for an unknown provider" do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:brave_search_api_key).and_return(nil)
      ENV.delete("BRAVE_SEARCH_API_KEY")
      ENV.delete("LEVELCODE_WEB_SEARCH_PROVIDER")
      expect(described_class.provider).to be_nil
      ENV["BRAVE_SEARCH_API_KEY"] = "k"
      expect(described_class.provider).to be_a(Levelcode::WebSearch::BraveProvider)
      ENV["LEVELCODE_WEB_SEARCH_PROVIDER"] = "bing"
      expect(described_class.provider).to be_nil
    end
  end

  describe ".run" do
    it "runs the queries at the same time and reports a failing or slow one without losing the others" do
      stub_const("Levelcode::WebSearch::QUERY_TIMEOUT", 0.2)
      provider = Object.new
      def provider.search(q, count:, recency:)
        sleep 0.15 if q == "a" || q == "b"
        raise "Brave Search answered HTTP 429" if q == "bad"
        sleep 5 if q == "slow"
        [ { title: q, url: "https://#{q}.org/", snippet: "", date: "" } ]
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      out = described_class.run(%w[a b bad slow], provider: provider, count: 3, recency: nil)
      took = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(out.map { |r| [ r[:query], r[:error] ] }).to eq([ [ "a", nil ], [ "b", nil ], [ "bad", "Brave Search answered HTTP 429" ], [ "slow", "timed out after 0.2 s" ] ])
      expect(took).to be < 2.0 # a and b in parallel, slow not waited on
    end
  end

  describe Levelcode::WebSearch::BraveProvider do
    it "asks with the key, extra snippets and freshness, and maps results to title, url, snippet and date" do
      seen = nil
      http = lambda do |uri, headers|
        seen = [ uri, headers ]
        [ 200, { web: { results: [ { title: "T", url: "https://t.org/", description: "Main", extra_snippets: %w[More Again Unused], page_age: "2026-03-01T00:00:00" } ] } }.to_json ]
      end
      results = described_class.new("KEY", http: http).search("csaf 2.1", count: 6, recency: "month")

      params = Rack::Utils.parse_query(seen[0].query)
      expect(seen[0].host).to eq("api.search.brave.com")
      expect(params).to include("q" => "csaf 2.1", "count" => "6", "extra_snippets" => "true", "freshness" => "pm")
      expect(seen[1]).to include("X-Subscription-Token" => "KEY")
      expect(results).to eq([ { title: "T", url: "https://t.org/", snippet: "Main … More … Again", date: "2026-03-01T00:00:00" } ])
    end

    it "raises on a non-200 answer, so that query is reported failed" do
      expect { described_class.new("K", http: ->(*) { [ 429, "{}" ] }).search("q", count: 1, recency: nil) }.to raise_error(/answered HTTP 429/)
    end
  end
end
