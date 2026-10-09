# frozen_string_literal: true

require "rails_helper"

# The grammar of a web editor's address: what an origin is, and what a URL to it is. Whether one is
# accepted — and what is done with one that is not — is Levelcode::EditorCallback's, and is specced there.
RSpec.describe Levelcode::WebEditor do
  describe ".origin" do
    it "is the entry itself when it is already an origin" do
      expect(described_class.origin("https://editor.levelcode.ai")).to eq("https://editor.levelcode.ai")
      expect(described_class.origin("https://editor.levelcode.ai:8443")).to eq("https://editor.levelcode.ai:8443")
    end

    it "folds the case of the scheme and the host, and trims the blanks round the entry" do
      expect(described_class.origin("  HTTPS://Editor.LevelCode.AI  ")).to eq("https://editor.levelcode.ai")
    end

    it "drops the port the scheme has by default, and keeps any other" do
      expect(described_class.origin("https://editor.levelcode.ai:443")).to eq("https://editor.levelcode.ai")
      expect(described_class.origin("http://localhost:80")).to eq("http://localhost")
      expect(described_class.origin("https://editor.levelcode.ai:80")).to eq("https://editor.levelcode.ai:80")
      expect(described_class.origin("http://localhost:443")).to eq("http://localhost:443")
    end

    describe "over http" do
      it "is for the machine in front of you: localhost, 127.0.0.1, [::1] and *.localhost" do
        %w[
          http://localhost
          http://localhost:5173
          http://127.0.0.1:3000
          http://[::1]:3000
          http://editor.localhost:8080
          http://a.b.localhost
        ].each do |entry|
          expect(described_class.origin(entry)).to eq(entry), entry
        end
      end

      it "is refused for anything else — the code would cross a network in the clear" do
        %w[
          http://editor.levelcode.ai
          http://levelcode.ai:3000
          http://127.0.0.2:3000
          http://192.168.1.10:5173
          http://localhost.evil.test
          http://evil-localhost
          http://notlocalhost
          http://[::2]:3000
        ].each do |entry|
          expect(described_class.origin(entry)).to be_nil, entry
        end
      end

      it "is refused for the bare suffix — `.localhost` is not a host" do
        expect(described_class.origin("http://.localhost")).to be_nil
      end
    end

    it "is nil for anything that is not exactly scheme://host[:port]" do
      {
        "a path" => "https://editor.levelcode.ai/",
        "a deeper path" => "https://editor.levelcode.ai/app",
        "a query" => "https://editor.levelcode.ai?x=1",
        "a fragment" => "https://editor.levelcode.ai#x",
        "userinfo" => "https://user@editor.levelcode.ai",
        "userinfo with a password" => "https://user:pw@editor.levelcode.ai",
        "a wildcard host" => "https://*.levelcode.ai",
        "a wildcard label" => "https://edit*.levelcode.ai",
        "a leading wildcard dot" => "https://.levelcode.ai",
        "a trailing dot" => "https://editor.levelcode.ai.",
        "an empty label" => "https://editor..levelcode.ai",
        "an empty port" => "https://editor.levelcode.ai:",
        "port 0" => "https://editor.levelcode.ai:0",
        "a port out of range" => "https://editor.levelcode.ai:65536",
        "a six-digit port" => "https://editor.levelcode.ai:100000",
        "a non-numeric port" => "https://editor.levelcode.ai:http",
        "no scheme" => "editor.levelcode.ai",
        "a scheme-relative address" => "//editor.levelcode.ai",
        "a scheme that is not http(s)" => "ftp://editor.levelcode.ai",
        "javascript" => "javascript://editor.levelcode.ai",
        "a LevelCode scheme" => "levelcode://levelcode.levelcode-ai",
        "a blank" => "",
        "whitespace inside" => "https://editor .levelcode.ai",
        "a tab inside" => "https://editor\t.levelcode.ai",
        "a newline after" => "https://editor.levelcode.ai\nhttps://evil.test",
        "an underscore" => "https://editor_1.levelcode.ai",
        "a leading hyphen" => "https://-editor.levelcode.ai",
        "a trailing hyphen" => "https://editor-.levelcode.ai",
        "non-ASCII" => "https://édítor.levelcode.ai",
        "the Kelvin sign, which case-folds to k" => "https://Keditor.levelcode.ai",
        "an encoded host" => "https://%65ditor.levelcode.ai",
        "a backslash" => "https://editor.levelcode.ai\\@evil.test",
        "two entries run together" => "https://a.example,https://b.example",
        "an IPv6 literal that is not one" => "https://[:::]",
        "an IPv6 literal with an IPv4 inside the brackets" => "https://[1.2.3.4]",
        "an IPv6 literal with a prefix" => "https://[::1/64]",
        "an empty IPv6 literal" => "https://[]",
        "a short IPv4 a browser would widen" => "https://1.2.3",
        "an IPv4 with an octet past 255" => "https://300.1.1.1",
        "an IPv4 as one number" => "https://2130706433",
        "an IPv4 in hex" => "https://0x7f.1",
        "a name that ends in a number" => "https://editor.1",
        "a name that ends in hex" => "https://editor.0x1f",
        "an IPv4 with a leading zero octet" => "https://127.00.0.1"
      }.each do |what, entry|
        expect(described_class.origin(entry)).to be_nil, "#{what}: #{entry.inspect}"
      end
    end

    it "takes the addresses that are what a browser would write" do
      expect(described_class.origin("https://127.0.0.1:8443")).to eq("https://127.0.0.1:8443")
      expect(described_class.origin("http://127.0.0.1:3000")).to eq("http://127.0.0.1:3000")
      expect(described_class.origin("https://[2001:db8::1]:8443")).to eq("https://[2001:db8::1]:8443")
      expect(described_class.origin("https://[::FFFF:127.0.0.1]")).to eq("https://[::ffff:127.0.0.1]")
      expect(described_class.origin("https://editor1.levelcode.ai")).to eq("https://editor1.levelcode.ai")
      expect(described_class.origin("https://1editor.levelcode.ai")).to eq("https://1editor.levelcode.ai")
    end

    it "is nil — never an exception — for what is not a string" do
      expect(described_class.origin(nil)).to be_nil
      expect(described_class.origin(42)).to be_nil
      expect(described_class.origin(%w[https://editor.levelcode.ai])).to be_nil
    end

    it "is nil — never an exception — for text that is not valid UTF-8" do
      expect(described_class.origin("https://editor\xFF.levelcode.ai".dup.force_encoding("UTF-8"))).to be_nil
      expect(described_class.origin("\xFF".dup.force_encoding("UTF-8"))).to be_nil
      expect(described_class.parse_url("https://editor.levelcode.ai/\xFF".dup.force_encoding("UTF-8"))).to be_nil
    end

    it "is nil for a host longer than a DNS name can be" do
      host = (%w[a] * 130).join(".")
      expect(host.length).to be > 253
      expect(described_class.origin("https://#{host}")).to be_nil
    end
  end

  describe ".parse_url" do
    it "is the origin and the path, apart" do
      expect(described_class.parse_url("https://editor.levelcode.ai")).to eq([ "https://editor.levelcode.ai", "" ])
      expect(described_class.parse_url("https://editor.levelcode.ai/")).to eq([ "https://editor.levelcode.ai", "/" ])
      expect(described_class.parse_url("https://editor.levelcode.ai/app/v2")).to eq([ "https://editor.levelcode.ai", "/app/v2" ])
    end

    it "reads the origin as .origin does, and leaves the case of the path alone" do
      expect(described_class.parse_url(" HTTPS://Editor.LevelCode.AI:443/App ")).to eq([ "https://editor.levelcode.ai", "/App" ])
      expect(described_class.parse_url("http://localhost:5173/")).to eq([ "http://localhost:5173", "/" ])
    end

    it "is nil when the origin would be refused" do
      expect(described_class.parse_url("http://editor.levelcode.ai/")).to be_nil
      expect(described_class.parse_url("https://*.levelcode.ai/")).to be_nil
      expect(described_class.parse_url("https://user@editor.levelcode.ai/")).to be_nil
    end

    it "is nil for a query, a fragment or anything in the path that is not a plain path character" do
      [
        "https://editor.levelcode.ai/?folder=/work",
        "https://editor.levelcode.ai?x=1",
        "https://editor.levelcode.ai/#x",
        "https://editor.levelcode.ai/a%2fb",
        "https://editor.levelcode.ai/a b",
        "https://editor.levelcode.ai/a;b",
        "https://editor.levelcode.ai/é"
      ].each do |entry|
        expect(described_class.parse_url(entry)).to be_nil, entry
      end
    end

    it "is nil — never an exception — for what is not a string" do
      expect(described_class.parse_url(nil)).to be_nil
      expect(described_class.parse_url("")).to be_nil
    end
  end

  describe ".origin_of" do
    it "writes a parsed URL's origin as the list does, default port dropped" do
      expect(described_class.origin_of(URI.parse("https://editor.levelcode.ai:443/callback.html?x=1"))).to eq("https://editor.levelcode.ai")
      expect(described_class.origin_of(URI.parse("http://localhost:5173/x"))).to eq("http://localhost:5173")
      expect(described_class.origin_of(URI.parse("http://[::1]:3000/x"))).to eq("http://[::1]:3000")
    end

    it "does not case-fold the host — a host that is not written as the list writes it is not on it" do
      expect(described_class.origin_of(URI.parse("https://EDITOR.levelcode.ai/x"))).to eq("https://EDITOR.levelcode.ai")
    end

    it "does not raise for an address with no host" do
      expect { described_class.origin_of(URI.parse("javascript:alert(1)")) }.not_to raise_error
    end
  end
end
