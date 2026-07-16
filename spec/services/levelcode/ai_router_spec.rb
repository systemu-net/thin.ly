# frozen_string_literal: true

require "rails_helper"

RSpec.describe Levelcode::AiRouter do
  # routed_body forces the tier's model AND normalizes prompt-caching breakpoints against that ROUTED
  # model — the client only guessed the upstream; the gateway knows it, so it owns the caching decision.
  def routed(body, model)
    described_class.new(body, model: model).send(:routed_body)
  end

  let(:system_msg) { { "role" => "system", "content" => "You are the agent." } }
  let(:user_msg)   { { "role" => "user", "content" => "fix the bug" } }
  let(:base_body)  { { "messages" => [ system_msg, user_msg ], "stream" => true } }

  describe "#routed_body" do
    it "overrides the request's model with the routed (tier) one" do
      out = routed(base_body.merge("model" => "anthropic/claude-opus-4-8"), "moonshotai/kimi-k2.7-code")
      expect(out["model"]).to eq("moonshotai/kimi-k2.7-code")
    end
  end

  describe "prompt-caching policy" do
    context "Anthropic/Claude upstream" do
      subject(:out) { routed(base_body, "anthropic/claude-sonnet-5") }

      it "adds a cache_control breakpoint to the system message (caches tools+system)" do
        sys = out["messages"].find { |m| m["role"] == "system" }
        expect(sys["content"]).to eq(
          [ { "type" => "text", "text" => "You are the agent.", "cache_control" => { "type" => "ephemeral" } } ]
        )
      end

      it "adds a cache_control breakpoint to the last message (caches the transcript prefix)" do
        expect(out["messages"].last["content"].last["cache_control"]).to eq("type" => "ephemeral")
      end

      it "treats both 'anthropic/…' and bare 'claude-…' ids as Anthropic-family" do
        %w[anthropic/claude-opus-4-8 claude-opus-4-8 anthropic/claude-fable-5].each do |m|
          sys = routed(base_body, m)["messages"].find { |x| x["role"] == "system" }
          expect(sys["content"]).to be_an(Array), "expected #{m} to be Anthropic-family"
        end
      end

      it "is idempotent — never double-marks a block the client already cached" do
        client_cached = { "messages" => [
          { "role" => "system", "content" => [ { "type" => "text", "text" => "sys", "cache_control" => { "type" => "ephemeral" } } ] },
          user_msg
        ] }
        sys = routed(client_cached, "anthropic/claude-sonnet-5")["messages"].first
        expect(sys["content"].size).to eq(1)
        expect(sys["content"][0]["cache_control"]).to eq("type" => "ephemeral")
      end
    end

    context "non-Anthropic upstream (a tier re-route away from Claude)" do
      it "STRIPS client-sent cache_control so it never reaches e.g. an OpenAI upstream that rejects it" do
        client_cached = { "messages" => [
          { "role" => "system", "content" => [ { "type" => "text", "text" => "sys", "cache_control" => { "type" => "ephemeral" } } ] },
          { "role" => "user",   "content" => [ { "type" => "text", "text" => "hi",  "cache_control" => { "type" => "ephemeral" } } ] }
        ] }
        out = routed(client_cached, "openai/gpt-5.5")
        out["messages"].each { |m| m["content"].each { |b| expect(b).not_to have_key("cache_control") } }
      end

      it "leaves a plain-string body untouched (nothing to strip)" do
        expect(routed(base_body, "moonshotai/kimi-k2.7-code")["messages"]).to eq(base_body["messages"])
      end

      # The matcher is a Claude-SEGMENT match, not an `anthropic/` prefix match: a future non-Claude
      # Anthropic model must not inherit the Claude-only cache_control field (it could reject the request).
      it "does NOT treat a non-Claude anthropic/* id as Anthropic-family" do
        sys = routed(base_body, "anthropic/some-future-nonclaude")["messages"].find { |m| m["role"] == "system" }
        expect(sys["content"]).to eq("You are the agent.") # untouched string → no breakpoint injected
      end

      it "does NOT match a look-alike id whose segment merely starts with 'claude'" do
        sys = routed(base_body, "anthropic/claudeXYZ")["messages"].find { |m| m["role"] == "system" }
        expect(sys["content"]).to eq("You are the agent.")
      end
    end

    context "safety" do
      it "reverts to pure pass-through when LEVELCODE_GATEWAY_CACHE=0" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("LEVELCODE_GATEWAY_CACHE").and_return("0")
        sys = routed(base_body, "anthropic/claude-sonnet-5")["messages"].find { |m| m["role"] == "system" }
        expect(sys["content"]).to eq("You are the agent.") # untouched string
      end

      it "does not mutate the caller's original body" do
        routed(base_body, "anthropic/claude-sonnet-5")
        expect(base_body["messages"].find { |m| m["role"] == "system" }["content"]).to eq("You are the agent.")
      end

      it "no-ops on a body with no messages" do
        expect(routed({ "stream" => true }, "anthropic/claude-sonnet-5")).to eq("model" => "anthropic/claude-sonnet-5", "stream" => true)
      end

      # The rescue runs with the user's prompt in scope, and NoMethodError interpolates the inspected
      # receiver — logging e.message would spill prompt text into the logs.
      it "logs the exception class + call site but NEVER e.message (it can carry prompt content)" do
        secret = "SECRET-PROMPT-TEXT"
        allow_any_instance_of(described_class).to receive(:mark_cacheable!)
          .and_raise(NoMethodError, %(undefined method 'x' for {"content"=>"#{secret}"}:Hash))

        logged = nil
        allow(Rails.logger).to receive(:warn) { |msg| logged = msg }

        out = routed(base_body, "anthropic/claude-sonnet-5")

        expect(logged).to include("NoMethodError")
        expect(logged).not_to include(secret)
        expect(out["messages"]).to eq(base_body["messages"]) # still passes the body through unchanged
      end
    end
  end
end
