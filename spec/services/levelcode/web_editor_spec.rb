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

  # The origin the editor's extension host runs on. Where it is isolated it is a cross-origin iframe on a
  # subdomain of its own per session — https://v--<hash>.ext.example.com — and every call an extension
  # makes to the API comes from there.
  describe ".extension_host" do
    def wildcard(entry)
      found = described_class.extension_host(entry)
      expect(found).to be_a(described_class::Wildcard), "#{entry.inspect} => #{found.inspect}"
      found
    end

    it "is the origin, as .origin takes one, for an entry that names one" do
      expect(described_class.extension_host("https://ext.example.com")).to eq("https://ext.example.com")
      expect(described_class.extension_host("https://ext.example.com:8443")).to eq("https://ext.example.com:8443")
      expect(described_class.extension_host(" HTTP://LocalHost:8801 ")).to eq("http://localhost:8801")
      expect(described_class.extension_host("https://v--abc.ext.example.com:443")).to eq("https://v--abc.ext.example.com")
    end

    it "refuses an origin as .origin refuses it" do
      [ "http://ext.example.com", "https://ext.example.com/", "https://user@ext.example.com", "ftp://ext.example.com",
        "https://ext.example.com.", "https://ext_1.example.com", "", "ext.example.com" ].each do |entry|
        expect(described_class.extension_host(entry)).to be_nil, entry
      end
    end

    describe "a wildcard" do
      it "is the scheme, the domain the star is a subdomain of, and the port" do
        found = wildcard("https://*.ext.example.com")
        expect([ found.scheme, found.parent, found.port ]).to eq([ "https", "ext.example.com", nil ])
        expect(found.to_s).to eq("https://*.ext.example.com")

        found = wildcard("https://*.ext.example.com:8443")
        expect([ found.scheme, found.parent, found.port ]).to eq([ "https", "ext.example.com", 8443 ])
        expect(found.to_s).to eq("https://*.ext.example.com:8443")
      end

      it "is case-folded and loses the port its scheme has anyway, as an origin does" do
        found = wildcard("  HTTPS://*.EXT.Example.COM:443 ")
        expect(found.to_s).to eq("https://*.ext.example.com")
        expect(found.port).to be_nil
        expect(wildcard("http://*.LocalHost:80").to_s).to eq("http://*.localhost")
      end

      it "is equal to another written the same way, and frozen" do
        expect(wildcard("https://*.ext.example.com")).to eq(wildcard("HTTPS://*.EXT.example.com:443"))
        expect(wildcard("https://*.ext.example.com")).to be_frozen
      end

      it "takes a domain of two labels or more, and any depth" do
        %w[https://*.example.com https://*.ext.example.com https://*.a.b.c.example.co.uk].each do |entry|
          wildcard(entry)
        end
      end

      it "takes localhost — over http, which is for development — and *.<something>.localhost" do
        expect(wildcard("http://*.localhost:8801").to_s).to eq("http://*.localhost:8801")
        expect(wildcard("http://*.localhost").to_s).to eq("http://*.localhost")
        expect(wildcard("http://*.ext.localhost:8801").to_s).to eq("http://*.ext.localhost:8801")
        expect(wildcard("http://*.a.b.localhost").to_s).to eq("http://*.a.b.localhost")
        expect(wildcard("https://*.localhost:8801").to_s).to eq("https://*.localhost:8801")
      end

      {
        "a single label, which is a top-level domain" => "https://*.com",
        "a single label that is not a TLD either" => "https://*.internal",
        "no domain at all" => "https://*",
        "a dot and nothing" => "https://*.",
        "an empty label" => "https://*..example.com",
        "a star that is part of a label" => "https://v--*.example.com",
        "a star at the front of a label" => "https://*abc.example.com",
        "a star at the end of a label" => "https://abc*.example.com",
        "two stars in a label" => "https://**.example.com",
        "two wildcards" => "https://*.*.example.com",
        "a star that is not the leftmost label" => "https://ext.*.example.com",
        "a star that is the last label" => "https://*.example.*",
        "a star in the middle of the domain" => "https://*.ext.*.example.com",
        "a star in the scheme" => "*://*.example.com",
        "a star in a scheme's name" => "http*://*.example.com",
        "a star as the port" => "https://*.example.com:*",
        "a star in the port" => "https://*.example.com:8*",
        "no scheme" => "*.example.com",
        "a scheme-relative address" => "//*.example.com",
        "a scheme that is not http(s)" => "ftp://*.example.com",
        "javascript:" => "javascript://*.example.com",
        "a path" => "https://*.example.com/",
        "a longer path" => "https://*.example.com/callback.html",
        "a query" => "https://*.example.com?x=1",
        "a fragment" => "https://*.example.com#x",
        "userinfo before the star" => "https://user@*.example.com",
        "the star as userinfo" => "https://*@example.com",
        "http for a domain that is not local" => "http://*.example.com",
        "http for a domain that only contains localhost" => "http://*.localhost.evil.com",
        "http for a domain that only ends like localhost" => "http://*.notlocalhost",
        "http for two labels that only end like localhost" => "http://*.evil.notlocalhost",
        "http for two labels, the last one hyphenated onto localhost" => "http://*.a.evil-localhost",
        "http for a domain whose suffix is not .localhost" => "http://*.evil-localhost",
        "an IPv4 address as the domain" => "https://*.127.0.0.1",
        "an IPv4 address as the domain over http" => "http://*.127.0.0.1:8801",
        "a short IPv4 as the domain" => "https://*.1.2.3",
        "a domain that ends in a number" => "https://*.ext.1",
        "a domain that ends in hex" => "https://*.ext.0x1f",
        "an IPv6 literal as the domain" => "https://*.[::1]",
        "port 0" => "https://*.example.com:0",
        "a port out of range" => "https://*.example.com:65536",
        "a six-digit port" => "https://*.example.com:100000",
        "an empty port" => "https://*.example.com:",
        "a trailing dot" => "https://*.example.com.",
        "an underscore" => "https://*.ex_ample.com",
        "a leading hyphen" => "https://*.-example.com",
        "a trailing hyphen in a label" => "https://*.example-.com",
        "whitespace inside" => "https://* .example.com",
        "a tab inside" => "https://*\t.example.com",
        "a newline after" => "https://*.example.com\nhttps://*.evil.com",
        "two entries run together" => "https://*.a.example.com,https://*.b.example.com",
        "non-ASCII" => "https://*.éxample.com",
        "an encoded domain" => "https://*.%65xample.com",
        "a backslash" => "https://*.example.com\\@evil.test",
        "a wildcard that is a label of an encoded star" => "https://%2A.example.com",
        "a domain longer than a name can be" => "https://*.#{(%w[a] * 130).join('.')}"
      }.each do |what, entry|
        it "is nil for #{what}" do
          expect(described_class.extension_host(entry)).to be_nil, entry.inspect
        end
      end

      it "is nil — never an exception — for what is not a string, or not valid text" do
        expect(described_class.extension_host(nil)).to be_nil
        expect(described_class.extension_host(42)).to be_nil
        expect(described_class.extension_host("https://*.\xFF.example.com".dup.force_encoding("UTF-8"))).to be_nil
        expect(described_class.extension_host("https://*.example.com/\xFF".dup.force_encoding("UTF-8"))).to be_nil
      end
    end
  end

  describe "the marker" do
    it "is `v--` and then one to sixty-three letters or digits, and the whole of the label" do
      marker = described_class::EXTENSION_HOST_LABEL
      expect([ "v--a", "v--abc123", "v--#{'a' * 52}", "v--#{'0' * 63}" ]).to all(match(marker))
      [ "v--", "v-a", "v---a", "V--abc", "xv--abc", "v--abc-", "v--a-b", "v--a_b", "v--#{'a' * 64}", "v--abc\n", "", "abc" ].each do |label|
        expect(label).not_to match(marker), label.inspect
      end
    end
  end

  describe ".wildcard_origin?" do
    let(:wildcards) { [ described_class.extension_host("https://*.ext.example.com") ] }

    def stands_for?(source, list = wildcards)
      described_class.wildcard_origin?(list, source)
    end

    it "is true for a subdomain whose label is the editor's own marker" do
      expect(stands_for?("https://v--abc123.ext.example.com")).to be(true)
      expect(stands_for?("https://v--a.ext.example.com")).to be(true)
      expect(stands_for?("https://v--#{'a1' * 26}.ext.example.com")).to be(true) # 52 characters, as the editor makes them
      expect(stands_for?("https://v--#{'z' * 60}.ext.example.com")).to be(true)  # a 63-character label: the longest one
    end

    # The marker pattern allows 63 characters after `v--`, but a DNS label is 63 characters in all, and
    # an origin is parsed as one: a longer label is no host a browser could have reached.
    it "is false for a label longer than a DNS label can be" do
      expect(stands_for?("https://v--#{'z' * 61}.ext.example.com")).to be(false)
      expect(stands_for?("https://v--#{'z' * 63}.ext.example.com")).to be(false)
    end

    it "is false for everything the coordinator's list refuses — each fails one comparison of parts" do
      {
        "another domain" => "https://evil.com",
        "the domain as a prefix of another" => "https://v--abc.ext.example.com.evil.com",
        "the domain with a label added in front of it" => "https://v--abc.evil.ext.example.com",
        "the marker one label too deep" => "https://x.v--abc.ext.example.com",
        "the wrong scheme" => "http://v--abc.ext.example.com",
        "a port the entry did not have" => "https://v--abc.ext.example.com:8443",
        "a label that only ends like the marker" => "https://notv.ext.example.com",
        "a label that is a longer word" => "https://xv--abc.ext.example.com",
        "the marker with nothing after it" => "https://v--.ext.example.com",
        "the marker with one hyphen" => "https://v-abc.ext.example.com",
        "the marker with three hyphens" => "https://v---abc.ext.example.com",
        "no marker at all" => "https://abc.ext.example.com",
        "the domain itself" => "https://ext.example.com",
        "a sibling domain" => "https://v--abc.other.example.com",
        "the parent of the domain" => "https://v--abc.example.com",
        "the marker with an underscore" => "https://v--a_c.ext.example.com",
        "a marker label of 64 characters after the hyphens" => "https://v--#{'a' * 64}.ext.example.com"
      }.each do |what, source|
        expect(stands_for?(source)).to be(false), "#{what}: #{source}"
      end
    end

    it "is false for an origin that is not written the way a browser writes one" do
      {
        "an upper-case label" => "https://V--ABC.ext.example.com",
        "an upper-case marker" => "https://V--abc.ext.example.com",
        "an upper-case domain" => "https://v--abc.EXT.example.com",
        "an upper-case scheme" => "HTTPS://v--abc.ext.example.com",
        "a mixed-case host" => "https://v--Abc.ext.example.com",
        "a default port written out" => "https://v--abc.ext.example.com:443",
        "a port with a leading zero" => "https://v--abc.ext.example.com:08443",
        "a trailing dot" => "https://v--abc.ext.example.com.",
        "a trailing slash" => "https://v--abc.ext.example.com/",
        "a path" => "https://v--abc.ext.example.com/x",
        "a query" => "https://v--abc.ext.example.com?x",
        "a fragment" => "https://v--abc.ext.example.com#x",
        "userinfo" => "https://user@v--abc.ext.example.com",
        "userinfo that makes it another host" => "https://v--abc.ext.example.com@evil.com",
        "userinfo with the marker as the user" => "https://v--abc@ext.example.com",
        "a space before" => " https://v--abc.ext.example.com",
        "a space after" => "https://v--abc.ext.example.com ",
        "a newline after" => "https://v--abc.ext.example.com\n",
        "a tab inside" => "https://v--abc\t.ext.example.com",
        "a backslash" => "https://v--abc.ext.example.com\\.evil.com",
        "an encoded dot" => "https://v--abc%2eext.example.com",
        "an encoded label" => "https://v%2d%2dabc.ext.example.com",
        "an encoded host" => "https://v--abc.ext.example%2ecom",
        "a scheme-relative address" => "//v--abc.ext.example.com",
        "no scheme" => "v--abc.ext.example.com",
        "the string null, as a sandboxed origin is written" => "null",
        "a wildcard, as an entry is written" => "https://*.ext.example.com",
        "a non-ASCII look-alike" => "https://v--abc.ext.exämple.com",
        "an empty string" => "",
        "a blank" => " "
      }.each do |what, source|
        expect(stands_for?(source)).to be(false), "#{what}: #{source.inspect}"
      end
    end

    it "is false — never an exception — for what is not text, or not valid text" do
      [ nil, 42, :sym, [], {}, Object.new, "\xFF".dup.force_encoding("UTF-8"),
        "https://v--abc.ext.example.com\xFF".dup.force_encoding("UTF-8") ].each do |source|
        expect { stands_for?(source) }.not_to raise_error
        expect(stands_for?(source)).to be(false), source.inspect
      end
    end

    it "compares the port: an entry with one stands for that port, an entry without one for the scheme's own" do
      with_port = [ described_class.extension_host("https://*.ext.example.com:8443") ]
      expect(stands_for?("https://v--abc.ext.example.com:8443", with_port)).to be(true)
      expect(stands_for?("https://v--abc.ext.example.com", with_port)).to be(false)
      expect(stands_for?("https://v--abc.ext.example.com:8444", with_port)).to be(false)
      expect(stands_for?("https://v--abc.ext.example.com:08443", with_port)).to be(false) # not how a browser writes it
      expect(stands_for?("https://v--abc.ext.example.com:008443", with_port)).to be(false)
      expect(stands_for?("https://v--abc.ext.example.com", wildcards)).to be(true)
      expect(stands_for?("https://v--abc.ext.example.com:8443", wildcards)).to be(false)
    end

    it "compares the scheme: http for an https entry, and https for an http one, are not it" do
      local = [ described_class.extension_host("http://*.localhost:8801") ]
      expect(stands_for?("http://v--abc.localhost:8801", local)).to be(true)
      expect(stands_for?("https://v--abc.localhost:8801", local)).to be(false)
      expect(stands_for?("http://v--abc.localhost", local)).to be(false)
      expect(stands_for?("http://v--abc.localhost:8802", local)).to be(false)
      expect(stands_for?("http://v--abc.ext.localhost:8801", local)).to be(false)
      expect(stands_for?("http://v--abc.localhost.evil.com:8801", local)).to be(false)
    end

    it "stands for the origin of any one of several entries, and for no other" do
      list = [ "https://*.ext.example.com", "https://*.other.example.org:8443", "http://*.localhost:8801" ]
               .map { |entry| described_class.extension_host(entry) }
      expect(stands_for?("https://v--abc.ext.example.com", list)).to be(true)
      expect(stands_for?("https://v--abc.other.example.org:8443", list)).to be(true)
      expect(stands_for?("http://v--abc.localhost:8801", list)).to be(true)
      expect(stands_for?("https://v--abc.other.example.org", list)).to be(false)
      expect(stands_for?("https://v--abc.ext.example.org", list)).to be(false)
    end

    it "is false for every origin when there is no wildcard" do
      expect(stands_for?("https://v--abc.ext.example.com", [])).to be(false)
    end
  end
end
