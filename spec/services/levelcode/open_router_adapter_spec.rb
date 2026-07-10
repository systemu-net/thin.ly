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
end
