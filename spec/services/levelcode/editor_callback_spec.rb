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

  # A development editor has its own scheme, and no server takes it unless told to.
  describe "extra schemes" do
    let(:dev_address) { "levelcode-dev://levelcode.levelcode-ai/auth/callback" }

    it "are none by default — the shipped schemes are the whole list" do
      expect(callback.schemes).to eq(%w[levelcode atom-plus-plus])
      expect(callback.ignored).to eq([])
      expect(callback.match?(dev_address)).to be(false)
    end

    it "are taken from a comma list — trimmed, case-folded, blanks and repeats dropped" do
      rule = described_class.new(extra_schemes: " levelcode-dev, LevelCode-Insiders ,,levelcode-dev,")
      expect(rule.schemes).to eq(%w[levelcode atom-plus-plus levelcode-dev levelcode-insiders])
      expect(rule.ignored).to eq([])
    end

    it "are accepted on top of the shipped schemes, never in place of them" do
      rule = described_class.new(extra_schemes: "levelcode-dev")
      expect(rule.match?("#{dev_address}?windowId=1")).to be(true)
      expect(rule.match?(address)).to be(true)
      expect(rule.match?("atom-plus-plus://levelcode.levelcode-ai/auth/callback")).to be(true)
    end

    it "leave the host and the path as exact as they were" do
      rule = described_class.new(extra_schemes: "levelcode-dev")
      expect(rule.match?("levelcode-dev://evil.example/auth/callback")).to be(false)
      expect(rule.match?("levelcode-dev://levelcode.levelcode-ai/elsewhere")).to be(false)
    end

    # The code is appended to whatever passes and the browser is sent there. `https` would post it
    # to a web host; `javascript` would run script on the account page.
    it "must be a LevelCode build's scheme — nothing a browser resolves itself can be added" do
      unusable = %w[https http javascript data file ws ftp vbscript intent about]
      rule = described_class.new(extra_schemes: unusable.join(","))

      expect(rule.schemes).to eq(%w[levelcode atom-plus-plus])
      expect(rule.ignored).to eq(unusable)
      unusable.each do |scheme|
        expect(rule.match?("#{scheme}://levelcode.levelcode-ai/auth/callback")).to be(false), scheme
      end
    end

    it "must be spelled as one: levelcode-<variant>" do
      misspelt = %w[levelcode_dev levelcode- -dev dev levelcode-dev:// levelcode--dev levelcode-dev- xlevelcode-dev levelcode-dév]
      rule = described_class.new(extra_schemes: misspelt.join(","))

      expect(rule.schemes).to eq(%w[levelcode atom-plus-plus])
      expect(rule.ignored).to eq(misspelt)
    end

    it "report an unusable entry as it was written, beside the ones that were taken" do
      rule = described_class.new(extra_schemes: "levelcode-dev, HTTPS")
      expect(rule.schemes).to eq(%w[levelcode atom-plus-plus levelcode-dev])
      expect(rule.ignored).to eq(%w[HTTPS])
    end

    it "do not report a shipped scheme named again — it is taken already" do
      rule = described_class.new(extra_schemes: "levelcode, Atom-Plus-Plus, levelcode-dev")
      expect(rule.schemes).to eq(%w[levelcode atom-plus-plus levelcode-dev])
      expect(rule.ignored).to eq([])
    end

    it "are none for an empty or missing list" do
      expect(described_class.new(extra_schemes: "").schemes).to eq(%w[levelcode atom-plus-plus])
      expect(described_class.new(extra_schemes: nil).schemes).to eq(%w[levelcode atom-plus-plus])
    end
  end

  # ENV is passed in rather than read, so "the list really comes from the environment" is an
  # assertion about behaviour (as in Levelcode::Hosts).
  describe ".from_env" do
    it "reads the extra schemes from the environment it is given" do
      rule = described_class.from_env("LEVELCODE_EXTRA_EDITOR_SCHEMES" => "levelcode-dev")
      expect(rule.schemes).to eq(%w[levelcode atom-plus-plus levelcode-dev])
    end

    it "takes no extra scheme when the setting is absent — what production runs with" do
      expect(described_class.from_env({}).schemes).to eq(%w[levelcode atom-plus-plus])
    end
  end

  describe ".current" do
    # Its own memo, so the process-wide rule is never disturbed.
    let(:fresh) { Class.new(described_class) }

    it "is built from the environment, once" do
      expect(fresh).to receive(:from_env).once.and_call_original
      expect(fresh.current).to equal(fresh.current)
      expect(fresh.current).to be_a(described_class)
    end

    it "says so in the log, once, when the setting names something it will not take" do
      allow(fresh).to receive(:from_env).and_return(described_class.new(extra_schemes: "levelcode-dev, https"))
      expect(Rails.logger).to receive(:warn).once.with(/LEVELCODE_EXTRA_EDITOR_SCHEMES: ignoring "https"/)

      2.times { fresh.current }
    end

    it "says nothing when every entry was taken" do
      allow(fresh).to receive(:from_env).and_return(described_class.new(extra_schemes: "levelcode-dev"))
      expect(Rails.logger).not_to receive(:warn)

      fresh.current
    end
  end

  it "is immutable" do
    rule = described_class.new(extra_schemes: "levelcode-dev, https")
    expect(rule).to be_frozen
    expect(rule.schemes).to be_frozen
    expect(rule.ignored).to be_frozen
  end
end
