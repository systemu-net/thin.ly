# frozen_string_literal: true

require "rails_helper"

RSpec.describe Levelcode::EditorCallback do
  subject(:callback) { described_class.new }

  let(:address) { "levelcode://levelcode.levelcode-ai/auth/callback" }

  describe "#match?" do
    it "is true for the editor's deep link, with or without a query" do
      expect(callback.match?(address)).to be(true)
      expect(callback.match?("#{address}?windowId=3")).to be(true)
    end

    it "takes a URI as readily as a string" do
      expect(callback.match?(URI.parse("#{address}?windowId=3"))).to be(true)
    end

    it "is true for each scheme on the list, and for no other" do
      expect(callback.schemes).to eq(%w[levelcode atom-plus-plus])
      expect(callback.match?("atom-plus-plus://levelcode.levelcode-ai/auth/callback")).to be(true)
      expect(callback.match?("levelcode-dev://levelcode.levelcode-ai/auth/callback")).to be(false)
      expect(callback.match?("https://levelcode.levelcode-ai/auth/callback")).to be(false)
    end

    it "reads the scheme as a URL does — its case is not part of it" do
      expect(callback.match?("LevelCode://levelcode.levelcode-ai/auth/callback")).to be(true)
    end

    it "compares the host and the path exactly" do
      expect(callback.match?("levelcode://evil.example/auth/callback")).to be(false)
      expect(callback.match?("levelcode://levelcode.levelcode-ai.evil.example/auth/callback")).to be(false)
      expect(callback.match?("levelcode://levelcode.levelcode-ai/auth/callback/extra")).to be(false)
      expect(callback.match?("levelcode://levelcode.levelcode-ai/auth")).to be(false)
      expect(callback.match?("levelcode://levelcode.levelcode-ai")).to be(false)
    end

    it "is false for an address with no host — the extension id sitting in the path proves nothing" do
      expect(callback.match?("levelcode:levelcode.levelcode-ai/auth/callback")).to be(false)
      expect(callback.match?("levelcode:/auth/callback")).to be(false)
    end

    it "is false — never an exception — for what is not an address at all" do
      expect(callback.match?("levelcode://not a url")).to be(false)
      expect(callback.match?("")).to be(false)
      expect(callback.match?(nil)).to be(false)
    end
  end
end
