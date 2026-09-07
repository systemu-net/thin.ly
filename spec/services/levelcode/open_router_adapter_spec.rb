# frozen_string_literal: true

require "rails_helper"

RSpec.describe Levelcode::OpenRouterAdapter do
  subject(:adapter) { described_class.new(api_key: "test-key") }

  # The stream loop raises UpstreamError on a terminal error frame so an in-stream
  # failure (after the 200 OK) is sanitized through the same controller boundary as a
  # pre-stream non-200 — the raw frame is never teed to the editor.
  describe "#error_frame_status (a private stream-loop helper)" do
    def status_of(payload) = adapter.send(:error_frame_status, payload)

    it "returns the numeric code of a terminal error frame" do
      expect(status_of('{"error":{"message":"credits exhausted","code":402}}')).to eq(402)
    end

    it "returns 0 for an error frame with no numeric code (falls through to the generic message)" do
      expect(status_of('{"error":{"message":"boom"}}')).to eq(0)
    end

    it "returns nil for a normal content chunk so a good chunk is never mistaken for an error" do
      expect(status_of('{"choices":[{"delta":{"content":"hi"}}]}')).to be_nil
    end

    it "returns nil for malformed / non-object payloads" do
      expect(status_of("not json")).to be_nil
      expect(status_of('["an","array"]')).to be_nil
      expect(status_of('{"usage":{"total_tokens":9}}')).to be_nil
    end
  end

  # Metering bills at the catalog rate and never reads OpenRouter's own cost, so the only thing
  # keeping wire cost <= billed cost is the price ceiling this helper injects. These pin its shape.
  describe "#with_provider_routing (a private request-shaping helper)" do
    def routed(body) = adapter.send(:with_provider_routing, body)

    it "pins the free model to FREE_MODEL_PROVIDER and never ceilings it" do
      out = routed("model" => Levelcode::FREE_MODEL, "messages" => [])
      expect(out["provider"]).to eq(described_class::FREE_MODEL_PROVIDER)
      expect(out["provider"]).not_to have_key("max_price")
    end

    it "leaves a client-supplied provider preference alone on the free model" do
      pref = { "order" => %w[fireworks] }
      expect(routed("model" => Levelcode::FREE_MODEL, "provider" => pref)["provider"]).to eq(pref)
    end

    it "ceilings a paid catalog model at exactly its catalog rate, in $/M" do
      row = Levelcode::ModelCatalog.find("openai/gpt-6-astra")
      out = routed("model" => "openai/gpt-6-astra", "messages" => [])
      expect(out["provider"]).to eq("max_price" => { "prompt" => 10.0, "completion" => 50.0 })
      expect(out["provider"]["max_price"]).to eq("prompt" => row[:input].to_f, "completion" => row[:output].to_f)
    end

    it "ceilings every confirmed paid row at its own rate (no model is left routable over price)" do
      Levelcode::ModelCatalog.ids.reject { |id| id == Levelcode::FREE_MODEL }.each do |id|
        row = Levelcode::ModelCatalog.find(id)
        mp = routed("model" => id)["provider"]["max_price"]
        expect(mp).to eq("prompt" => row[:input].to_f, "completion" => row[:output].to_f), id
      end
    end

    it "merges the ceiling ON TOP of a client preference — steering is kept, the ceiling cannot be lifted" do
      out = routed("model" => "anthropic/claude-opus-5",
                   "provider" => { "sort" => "throughput", "max_price" => { "prompt" => 99.0, "completion" => 999.0 } })
      expect(out["provider"]["sort"]).to eq("throughput")
      expect(out["provider"]["max_price"]).to eq("prompt" => 5.0, "completion" => 25.0)
    end

    it "leaves an off-catalog model untouched (nothing to ceiling against)" do
      body = { "model" => "vendor/not-in-catalog", "messages" => [] }
      expect(routed(body)).to eq(body)
    end

    it "does not mutate the caller's body" do
      body = { "model" => "openai/gpt-6-astra" }.freeze
      expect { routed(body) }.not_to raise_error
      expect(body).not_to have_key("provider")
    end
  end

  # The helper above is only worth anything if #stream and #complete actually route through it. No
  # spec drives those (the request specs double the router), so pin them at the adapter's own wire
  # seam: build_request is what serialises the upstream body, so the body it receives IS the wire.
  # A sentinel stops the call before any socket is opened.
  describe "#stream / #complete put the provider routing on the wire" do
    sentinel = Class.new(StandardError)
    let(:sent) { {} }

    before do
      allow(adapter).to receive(:build_request) do |_uri, body|
        sent.replace(body)
        raise sentinel
      end
    end

    it "#stream sends the price ceiling for a paid model" do
      expect { adapter.stream({ "model" => "openai/gpt-6-astra", "messages" => [] }, on_chunk: ->(_) { }) }.to raise_error(sentinel)
      expect(sent["provider"]).to eq("max_price" => { "prompt" => 10.0, "completion" => 50.0 })
      expect(sent["stream"]).to be(true)
    end

    it "#complete sends the price ceiling for a paid model" do
      expect { adapter.complete("model" => "anthropic/claude-opus-5", "messages" => []) }.to raise_error(sentinel)
      expect(sent["provider"]).to eq("max_price" => { "prompt" => 5.0, "completion" => 25.0 })
      expect(sent["stream"]).to be(false)
    end

    it "#stream still pins the free model to FREE_MODEL_PROVIDER" do
      expect { adapter.stream({ "model" => Levelcode::FREE_MODEL, "messages" => [] }, on_chunk: ->(_) { }) }.to raise_error(sentinel)
      expect(sent["provider"]).to eq(described_class::FREE_MODEL_PROVIDER)
    end
  end
end
