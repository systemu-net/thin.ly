# frozen_string_literal: true

require "net/http"

module Levelcode
  # Web search for the editor's agent (its `web_search` tool; levelcode docs/WEB-SEARCH.md). One request carries
  # 1-4 queries; they run at the same time against the configured search API and are billed per query that
  # answered, like a model turn: reserved up front, settled after, one ledger row (Api::Levelcode::V1::AiWebController).
  #
  # The provider is configured, not hard-wired: LEVELCODE_WEB_SEARCH_PROVIDER (default "brave") and its key in
  # BRAVE_SEARCH_API_KEY or credentials[:brave_search_api_key]. No key → `provider` is nil → the endpoint answers 503
  # and the editor tells the model web search is not available, so nothing breaks before the owner sets one.
  module WebSearch
    module_function

    MAX_QUERIES = 4
    MAX_QUERY_CHARS = 400
    DEFAULT_COUNT = 6
    MAX_COUNT = 10
    RECENCY = %w[day week month year].freeze
    QUERY_TIMEOUT = 6 # seconds; a query that has not answered by then is reported failed, not waited on

    # What one query costs US, in internal COST micro-$ (the wallet's basis). Brave's Data for AI plan lists $5 per
    # thousand queries; set LEVELCODE_WEB_SEARCH_COST_MICROS to the provider's real price. Retail is derived from it
    # by the same margin as tokens (Levelcode.retail_micros).
    def cost_micros_per_query
      Integer(ENV.fetch("LEVELCODE_WEB_SEARCH_COST_MICROS", "5000"))
    end

    def provider
      name = ENV.fetch("LEVELCODE_WEB_SEARCH_PROVIDER", "brave").to_s
      case name
      when "brave"
        key = ENV["BRAVE_SEARCH_API_KEY"].presence || Rails.application.credentials.dig(:brave_search_api_key).presence
        key && BraveProvider.new(key)
      end
    end

    # The editor's queries, cleaned: trimmed, de-duplicated (any case), at most four of at most 400 characters.
    def clean_queries(raw)
      Array(raw).map { |q| q.to_s.squish.first(MAX_QUERY_CHARS) }.reject(&:blank?).uniq(&:downcase).first(MAX_QUERIES)
    end

    # Every query at once. Answers one entry per query, in order: { query:, results: [...] } or { query:, results: [], error: }.
    def run(queries, provider:, count:, recency:)
      threads = queries.map do |q|
        Thread.new do
          { query: q, results: provider.search(q, count: count, recency: recency) }
        rescue => e
          { query: q, results: [], error: e.message.to_s.first(200) }
        end
      end
      threads.each_with_index.map do |t, i|
        next t.value if t.join(QUERY_TIMEOUT + 1)

        t.kill
        { query: queries[i], results: [], error: "timed out after #{QUERY_TIMEOUT} s" }
      end
    end

    # Brave Search's web endpoint. `http` is the seam the specs replace: (uri, headers) -> [status, body].
    class BraveProvider
      ENDPOINT = "https://api.search.brave.com/res/v1/web/search"
      FRESHNESS = { "day" => "pd", "week" => "pw", "month" => "pm", "year" => "py" }.freeze

      attr_reader :name

      def initialize(key, http: nil)
        @key = key
        @http = http || method(:get)
        @name = "brave"
      end

      def search(query, count:, recency:)
        params = { q: query, count: count, extra_snippets: true, text_decorations: false }
        params[:freshness] = FRESHNESS[recency] if FRESHNESS[recency]
        uri = URI(ENDPOINT)
        uri.query = URI.encode_www_form(params)
        status, body = @http.call(uri, { "Accept" => "application/json", "X-Subscription-Token" => @key })
        raise "Brave Search answered HTTP #{status}" unless status == 200

        Array(JSON.parse(body).dig("web", "results")).map do |r|
          {
            title: r["title"].to_s,
            url: r["url"].to_s,
            snippet: [ r["description"], *Array(r["extra_snippets"]).first(2) ].compact.join(" … "),
            date: r["page_age"].to_s
          }
        end
      end

      private

      def get(uri, headers)
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: QUERY_TIMEOUT) do |h|
          req = Net::HTTP::Get.new(uri)
          headers.each { |k, v| req[k] = v }
          res = h.request(req)
          [ res.code.to_i, res.body.to_s ]
        end
      end
    end
  end
end
