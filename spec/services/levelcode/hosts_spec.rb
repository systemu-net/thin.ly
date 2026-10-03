# frozen_string_literal: true

require "rails_helper"

RSpec.describe Levelcode::Hosts do
  subject(:policy) do
    described_class.new(hosts: "levelcode.ai, WWW.LevelCode.ai ,thinly.ngrok.app,", origin: "https://LevelCode.ai")
  end

  describe "the host list" do
    it "is parsed from a comma list — trimmed, case-folded, blanks dropped" do
      expect(policy.hosts).to eq(%w[levelcode.ai www.levelcode.ai thinly.ngrok.app])
    end

    it "is empty for an empty or missing list" do
      expect(described_class.new(hosts: "", origin: "https://levelcode.ai").hosts).to eq([])
      expect(described_class.new(hosts: nil, origin: "https://levelcode.ai").hosts).to eq([])
    end
  end

  describe "#include?" do
    it "folds case — Rack hands the Host header through exactly as the client sent it" do
      expect(policy.include?("levelcode.ai")).to be(true)
      expect(policy.include?("LevelCode.AI")).to be(true)
      expect(policy.include?("WWW.LEVELCODE.AI")).to be(true)
    end

    it "is false for the shortener host, nothing, and nil" do
      expect(policy.include?("thin.ly")).to be(false)
      expect(policy.include?("")).to be(false)
      expect(policy.include?(nil)).to be(false)
    end
  end

  describe "#origin?" do
    it "is true for the canonical origin's own host, whatever the case" do
      expect(policy.origin?("levelcode.ai")).to be(true)
      expect(policy.origin?("LEVELCODE.AI")).to be(true)
    end

    it "is false for any other host, and for nil" do
      expect(policy.origin?("thin.ly")).to be(false)
      expect(policy.origin?("www.levelcode.ai")).to be(false)
      expect(policy.origin?(nil)).to be(false)
    end

    it "compares the origin's host only — scheme, port and path are not part of the question" do
      tunnel = described_class.new(hosts: "", origin: "https://thinly.ngrok.app:8443/ai")
      expect(tunnel.origin?("thinly.ngrok.app")).to be(true)
      expect(tunnel.origin).to eq("https://thinly.ngrok.app:8443/ai")
    end

    it "is false — never an exception — when the origin is not a URL at all" do
      broken = described_class.new(hosts: "levelcode.ai", origin: "http://not a url")
      expect(broken.origin?("levelcode.ai")).to be(false)
      expect(broken.origin?("not a url")).to be(false)
    end
  end

  # ENV is passed in rather than read, so "the list really comes from the environment" is an
  # assertion about behaviour. The constants this replaced were frozen at class load, and the only
  # way to check that was a regex over the controller's source.
  describe ".from_env" do
    it "reads both settings from the environment it is given" do
      policy = described_class.from_env("LEVELCODE_HOSTS" => "a.test, B.test", "LEVELCODE_ORIGIN" => "https://a.test")
      expect(policy.hosts).to eq(%w[a.test b.test])
      expect(policy.origin).to eq("https://a.test")
    end

    it "falls back to the production defaults when a setting is absent" do
      policy = described_class.from_env({})
      expect(policy.hosts).to eq(%w[levelcode.ai www.levelcode.ai])
      expect(policy.origin).to eq("https://levelcode.ai")
    end

    # LEVELCODE_ORIGIN set, LEVELCODE_HOSTS not: the tunnel is the origin without being a LevelCode
    # host. That gap is exactly what StaticController#ui's self-redirect guard exists for.
    it "takes each setting independently, so a half-applied override is representable" do
      policy = described_class.from_env("LEVELCODE_ORIGIN" => "https://thinly.ngrok.app")
      expect(policy.include?("thinly.ngrok.app")).to be(false)
      expect(policy.origin?("thinly.ngrok.app")).to be(true)
    end
  end

  describe ".current" do
    it "is built from the environment, once" do
      fresh = Class.new(described_class) # its own memo, so the process-wide policy is never disturbed
      expect(fresh).to receive(:from_env).once.and_call_original
      expect(fresh.current).to equal(fresh.current)
      expect(fresh.current).to be_a(described_class)
    end
  end

  it "is immutable" do
    expect(policy).to be_frozen
    expect(policy.hosts).to be_frozen
  end
end
