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

  # The web edition of the editor: the same sign-in, handed to a page on an origin of its own. The
  # address it hands the code to is the page's /callback.html, carrying the deep link it stands for.
  # The code is appended to whatever passes, so each example here is a place it must not go — or the
  # one place it must.
  describe "the web editor" do
    let(:origin) { "https://editor.levelcode.test" }
    let(:rule) { described_class.new(web_origins: origin) }

    # What the editor's own code makes of asExternalUri(levelcode://levelcode.levelcode-ai/auth/callback):
    # its page, with the address it stands for in the vscode-* parameters (encodeURIComponent'd).
    vscode_params = { "vscode-reqid" => "7", "vscode-scheme" => "levelcode",
                      "vscode-authority" => "levelcode.levelcode-ai", "vscode-path" => "/auth/callback" }.freeze
    let(:vscode) { vscode_params }

    def callback(params = vscode, base: origin, path: "/callback.html")
      "#{base}#{path}?#{URI.encode_www_form(params)}"
    end

    # The same, written out — so the examples above are not only the helper agreeing with itself.
    let(:observed) do
      "https://editor.levelcode.test/callback.html?vscode-reqid=1&vscode-scheme=levelcode" \
        "&vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback"
    end

    describe "when the server has not been told of one (production)" do
      subject(:off) { described_class.new }

      it "has no origin, is off, and has nowhere to send anyone" do
        expect(off.web_origins).to eq([])
        expect(off.web_enabled?).to be(false)
        expect(off.web_url).to be_nil
        expect(off.ignored_web_origins).to eq([])
        expect(off.ignored_web_url).to be_nil
      end

      it "takes no web address — not even the one the editor would produce" do
        expect(off.match?(observed)).to be(false)
        expect(off.match?(callback)).to be(false)
        expect(off.match?(callback(base: "http://localhost:5173"))).to be(false)
      end

      it "takes no origin for CORS" do
        expect(off.web_origin?("https://editor.levelcode.test")).to be(false)
        expect(off.web_origin?(nil)).to be(false)
      end

      it "is the same rule as before for the deep link" do
        expect(off.match?(address)).to be(true)
        expect(off.match?("#{address}?windowId=3")).to be(true)
        expect(off.match?("levelcode://evil.example/auth/callback")).to be(false)
        expect(off.match?("https://levelcode.levelcode-ai/auth/callback")).to be(false)
      end

      it "is no more on for a setting that names nothing usable" do
        rule = described_class.new(web_origins: " , ftp://x, https://*.levelcode.test, http://editor.levelcode.test", web_url: "https://editor.levelcode.test/")
        expect(rule.web_enabled?).to be(false)
        expect(rule.web_origins).to eq([])
        expect(rule.web_url).to be_nil
        expect(rule.match?(observed)).to be(false)
      end
    end

    describe "#match? on a server that has been told of one" do
      it "takes the callback the editor builds, with or without a query of its own" do
        expect(rule.match?(observed)).to be(true)
        expect(rule.match?(callback)).to be(true)
        expect(rule.match?(callback(vscode.merge("vscode-query" => "windowId=3")))).to be(true)
      end

      it "takes a URI as readily as a string" do
        expect(rule.match?(URI.parse(observed))).to be(true)
      end

      it "reads the parameters in any order, with others beside them" do
        shuffled = vscode.to_a.reverse.to_h.merge("utm_x" => "1", "state" => "abc")
        expect(rule.match?(callback(shuffled))).to be(true)
        expect(rule.match?(callback({ "a" => "1" }.merge(vscode)))).to be(true)
      end

      it "reads them as the page does: percent-decoded, so the path may arrive encoded or plain" do
        expect(rule.match?(observed)).to be(true)
        plain = "#{origin}/callback.html?vscode-reqid=7&vscode-scheme=levelcode" \
                "&vscode-authority=levelcode.levelcode-ai&vscode-path=/auth/callback"
        expect(rule.match?(plain)).to be(true)
      end

      it "is true for each scheme the deep link takes, and for no other" do
        expect(rule.match?(callback(vscode.merge("vscode-scheme" => "atom-plus-plus")))).to be(true)
        expect(rule.match?(callback(vscode.merge("vscode-scheme" => "levelcode-dev")))).to be(false)
        expect(rule.match?(callback(vscode.merge("vscode-scheme" => "vscode")))).to be(false)
        expect(rule.match?(callback(vscode.merge("vscode-scheme" => "https")))).to be(false)
        expect(rule.match?(callback(vscode.merge("vscode-scheme" => "javascript")))).to be(false)

        dev = described_class.new(extra_schemes: "levelcode-dev", web_origins: origin)
        expect(dev.match?(callback(vscode.merge("vscode-scheme" => "levelcode-dev")))).to be(true)
      end

      # It reads the address it is given. The extension sends the callback with its query percent-encoded
      # as one component; the gates decode that until stable BEFORE they ask, and ask about, and use, the
      # decoded address. A rule that decoded for itself would be validating something it did not return.
      it "reads the address as given — a query that is one encoded blob is not a callback until it is decoded" do
        blob = "#{origin}/callback.html?#{ERB::Util.url_encode(URI.encode_www_form(vscode))}"

        expect(rule.match?(blob)).to be(false)
        expect(rule.match?(CGI.unescape(blob))).to be(true)
      end

      it "takes an origin written with its default port: the browser says the same thing" do
        expect(rule.match?(callback(base: "https://editor.levelcode.test:443"))).to be(true)
      end

      it "takes every origin on the list, and only those" do
        two = described_class.new(web_origins: "https://editor.levelcode.test, https://other.levelcode.test:8443")
        expect(two.match?(callback(base: "https://editor.levelcode.test"))).to be(true)
        expect(two.match?(callback(base: "https://other.levelcode.test:8443"))).to be(true)
        expect(two.match?(callback(base: "https://other.levelcode.test"))).to be(false)
        expect(two.match?(callback(base: "https://third.levelcode.test"))).to be(false)
      end

      it "takes a local development origin over http, and only when the list names it" do
        dev = described_class.new(web_origins: "http://localhost:5173")
        expect(dev.match?(callback(base: "http://localhost:5173"))).to be(true)
        expect(dev.match?(callback(base: "http://localhost:5174"))).to be(false)
        expect(dev.match?(callback(base: "http://127.0.0.1:5173"))).to be(false)
        expect(dev.match?(callback(base: "https://localhost:5173"))).to be(false)
        expect(rule.match?(callback(base: "http://localhost:5173"))).to be(false)
      end

      # The one-time code is appended to whatever passes and the browser is sent there.
      describe "refuses" do
        let(:query) { URI.encode_www_form(vscode) }

        {
          # --- where the code would go ---
          "an origin that is not on the list" =>
            "https://evil.test/callback.html?%<query>s",
          "userinfo that makes the listed host the credentials of another" =>
            "https://editor.levelcode.test@evil.test/callback.html?%<query>s",
          "userinfo in front of the listed host" =>
            "https://evil.test@editor.levelcode.test/callback.html?%<query>s",
          "userinfo with a password in front of the listed host" =>
            "https://evil.test:pw@editor.levelcode.test/callback.html?%<query>s",
          "the listed host as a prefix of another" =>
            "https://editor.levelcode.test.evil.test/callback.html?%<query>s",
          "the listed host as a suffix of another" =>
            "https://eviledtor.levelcode.test/callback.html?%<query>s",
          "a sibling subdomain" =>
            "https://other.levelcode.test/callback.html?%<query>s",
          "the parent domain" =>
            "https://levelcode.test/callback.html?%<query>s",
          "another port of the listed host" =>
            "https://editor.levelcode.test:444/callback.html?%<query>s",
          "the port of the scheme it is not (http's, on https)" =>
            "https://editor.levelcode.test:80/callback.html?%<query>s",
          "http for the listed https origin (a downgrade)" =>
            "http://editor.levelcode.test/callback.html?%<query>s",
          "the listed host with a trailing dot — another origin to a browser" =>
            "https://editor.levelcode.test./callback.html?%<query>s",
          "the listed host in upper case — the editor's own address is never written so" =>
            "https://EDITOR.levelcode.test/callback.html?%<query>s",
          "an encoded host" =>
            "https://%%65ditor.levelcode.test/callback.html?%<query>s",
          "three slashes — an empty authority, then the host in the path" =>
            "https:///editor.levelcode.test/callback.html?%<query>s",
          "four slashes, which a browser reads as the host that follows" =>
            "https:////editor.levelcode.test/callback.html?%<query>s",
          "one slash — no authority at all" =>
            "https:/editor.levelcode.test/callback.html?%<query>s",
          "no slash" =>
            "https:editor.levelcode.test/callback.html?%<query>s",
          "a backslash a browser reads as a slash" =>
            "https://evil.test\\@editor.levelcode.test/callback.html?%<query>s",
          "a backslash after the host" =>
            "https://editor.levelcode.test\\.evil.test/callback.html?%<query>s",
          "a tab a browser would strip" =>
            "https://editor.levelcode.test\t.evil.test/callback.html?%<query>s",
          "a newline" =>
            "https://editor.levelcode.test/callback.html\n?%<query>s",
          "a leading space" =>
            " https://editor.levelcode.test/callback.html?%<query>s",
          "a scheme-relative address" =>
            "//editor.levelcode.test/callback.html?%<query>s",
          "javascript:" =>
            "javascript://editor.levelcode.test/callback.html?%<query>s",
          "data:" =>
            "data:text/html,<script>1</script>",
          "a different custom scheme on the listed host" =>
            "levelcode://editor.levelcode.test/callback.html?%<query>s",
          "the deep link's own path, on the listed origin" =>
            "https://editor.levelcode.test/auth/callback?%<query>s",
          # --- which page receives it ---
          "another page of the listed origin" =>
            "https://editor.levelcode.test/index.html?%<query>s",
          "the root of the listed origin" =>
            "https://editor.levelcode.test/?%<query>s",
          "a path under the callback page" =>
            "https://editor.levelcode.test/callback.html/extra?%<query>s",
          "a path that climbs out of it" =>
            "https://editor.levelcode.test/callback.html/../index.html?%<query>s",
          "a path that climbs in" =>
            "https://editor.levelcode.test/x/../callback.html?%<query>s",
          "an encoded slash after the page" =>
            "https://editor.levelcode.test/callback.html%%2f?%<query>s",
          "an encoded dot in the page's name" =>
            "https://editor.levelcode.test/callback%%2ehtml?%<query>s",
          "a doubled leading slash" =>
            "https://editor.levelcode.test//callback.html?%<query>s",
          "another host inside the path" =>
            "https://editor.levelcode.test//evil.test/callback.html?%<query>s",
          "the page in another case" =>
            "https://editor.levelcode.test/Callback.html?%<query>s",
          "a path parameter" =>
            "https://editor.levelcode.test/callback.html;x=1?%<query>s",
          "a trailing slash" =>
            "https://editor.levelcode.test/callback.html/?%<query>s",
          # --- nothing but the page and its query ---
          "a fragment" =>
            "https://editor.levelcode.test/callback.html?%<query>s#x",
          "an empty fragment" =>
            "https://editor.levelcode.test/callback.html?%<query>s#",
          "no query at all" =>
            "https://editor.levelcode.test/callback.html"
        }.each do |what, template|
          it "#{what}" do
            address = format(template, query: query)
            expect(rule.match?(address)).to be(false), address.inspect
          end
        end

        # What the page is told to do with the code — it dispatches whatever it is given, to whichever
        # extension registered that address.
        {
          "another extension's authority" => { "vscode-authority" => "vscode.github-authentication" },
          "the right authority in another case" => { "vscode-authority" => "LevelCode.levelcode-ai" },
          "the authority with a suffix" => { "vscode-authority" => "levelcode.levelcode-ai.evil" },
          "no authority" => { "vscode-authority" => nil },
          "an empty authority" => { "vscode-authority" => "" },
          "another path" => { "vscode-path" => "/did-authenticate" },
          "the path with a suffix" => { "vscode-path" => "/auth/callback/x" },
          "the path with a trailing slash" => { "vscode-path" => "/auth/callback/" },
          "no path" => { "vscode-path" => nil },
          "a scheme that is not an editor's" => { "vscode-scheme" => "vscode" },
          "an empty scheme" => { "vscode-scheme" => "" },
          "no scheme" => { "vscode-scheme" => nil },
          "a scheme in another case" => { "vscode-scheme" => "LevelCode" },
          "no request id" => { "vscode-reqid" => nil },
          "an empty request id" => { "vscode-reqid" => "" },
          "a request id that is not a number" => { "vscode-reqid" => "abc" },
          "a negative request id" => { "vscode-reqid" => "-1" },
          "a request id with a sign" => { "vscode-reqid" => "+7" },
          "a request id of ten digits" => { "vscode-reqid" => "1234567890" },
          "a request id with a newline after it" => { "vscode-reqid" => "7\n" },
          "a request id with a space" => { "vscode-reqid" => "7 " },
          "a request id that is not ASCII" => { "vscode-reqid" => "٧" },
          "a request id of two numbers" => { "vscode-reqid" => "7,8" }
        }.each do |what, change|
          it "#{what}" do
            params = vscode.merge(change).compact
            expect(rule.match?(callback(params))).to be(false), params.inspect
          end
        end

        # The page takes the FIRST of a repeated parameter; a reader that takes the last sees another
        # address than the one that passed. Neither is let through.
        describe "a vscode-* parameter given twice" do
          good = { "vscode-query" => "a=1", "vscode-fragment" => "x" }

          %w[vscode-authority vscode-path vscode-scheme vscode-reqid vscode-query vscode-fragment].each do |key|
            right = good.fetch(key) { vscode_params.fetch(key) }
            wrong = key == "vscode-reqid" ? "9" : "evil"

            [ [ right, wrong ], [ wrong, right ] ].each do |first, second|
              it "#{key}: #{first} and then #{second}" do
                address = "#{callback(vscode.except(key))}&#{key}=#{first}&#{key}=#{second}"
                expect(rule.match?(address)).to be(false), address
              end
            end
          end

          it "spelled through percent-encoding" do
            expect(rule.match?("#{callback}&vscode%2Dauthority=evil.extension")).to be(false)
            expect(rule.match?("#{callback}&%76scode-authority=evil.extension")).to be(false)
          end

          it "with the same value twice" do
            expect(rule.match?("#{callback}&vscode-authority=levelcode.levelcode-ai")).to be(false)
          end

          it "but a name that only begins like one is another parameter" do
            expect(rule.match?("#{callback}&vscode_authority=evil&Vscode-Authority=evil&xvscode-authority=evil")).to be(true)
          end
        end

        # callback.html merges `vscode-query` into the query it hands the extension, and a name there
        # replaces the top-level parameter of the same name: the code this server appends would be
        # displaced by one the address supplied.
        describe "a vscode-query that could displace the one-time code" do
          {
            "naming code" => "code=attacker",
            "naming code among others" => "windowId=3&code=attacker",
            "naming code first" => "code=attacker&windowId=3",
            "naming code, encoded" => "%63ode=attacker",
            "naming code, encoded twice" => "%2563ode=attacker",
            "naming code, encoded three times" => "%252563ode=attacker",
            "an ampersand, encoded, before code" => "a=1%26code=attacker",
            "an ampersand, encoded twice, before code" => "a=1%2526code=attacker",
            "an ampersand, encoded three times, before code" => "a=1%252526code=attacker",
            "an equals sign, encoded" => "code%3Dattacker",
            "anything that is not a plain pair" => "windowId",
            "an empty name" => "=1",
            "a space" => "a=1 b",
            "a plus" => "a=1+b",
            "a percent sign" => "a=%41",
            "a slash" => "a=/etc/passwd",
            "a semicolon" => "a=1;code=attacker",
            "an empty query that is not absent" => ""
          }.each do |what, value|
            it "refuses #{what}" do
              address = callback(vscode.merge("vscode-query" => value))
              expect(rule.match?(address)).to be(false), address.inspect
            end
          end

          it "takes a plain pair, or several, that do not name it" do
            expect(rule.match?(callback(vscode.merge("vscode-query" => "windowId=3")))).to be(true)
            expect(rule.match?(callback(vscode.merge("vscode-query" => "windowId=3&folder=work")))).to be(true)
            expect(rule.match?(callback(vscode.merge("vscode-query" => "a=")))).to be(true)
            expect(rule.match?(callback(vscode.merge("vscode-query" => "decode=1&codex=2")))).to be(true)
          end

          it "is not provoked by a code at the top level — the one this server appends replaces it" do
            expect(rule.match?(callback(vscode.merge("code" => "attacker")))).to be(true)
          end
        end
      end

      it "leaves the deep link exactly as it was" do
        expect(rule.match?(address)).to be(true)
        expect(rule.match?("#{address}?windowId=3")).to be(true)
        expect(rule.match?("atom-plus-plus://levelcode.levelcode-ai/auth/callback")).to be(true)
        expect(rule.match?("levelcode-dev://levelcode.levelcode-ai/auth/callback")).to be(false)
        expect(rule.match?("levelcode://evil.example/auth/callback")).to be(false)
        expect(rule.match?("levelcode://levelcode.levelcode-ai/auth/callback/extra")).to be(false)
        expect(rule.match?("levelcode:/auth/callback")).to be(false)
      end

      it "does not turn an origin that is on the list into a host the deep link's path is taken at" do
        listed = described_class.new(web_origins: "https://levelcode.levelcode-ai")
        expect(listed.match?("https://levelcode.levelcode-ai/auth/callback")).to be(false)
        expect(listed.match?("https://levelcode.levelcode-ai/auth/callback?#{URI.encode_www_form(vscode)}")).to be(false)
      end

      it "is false — never an exception — for what is not an address at all, or not text at all" do
        [ "https://editor.levelcode.test/callback.html?%zz", "https://editor.levelcode.test/\u0000", "\xFF\xFE",
          "https://editor.levelcode.test/callback.html?vscode-reqid=%FF&#{URI.encode_www_form(vscode.except('vscode-reqid'))}",
          "https://editor.levelcode.test/callback.html?%FF=1&#{URI.encode_www_form(vscode)}", "", nil, 42, [], {}, Object.new ].each do |input|
          expect { rule.match?(input) }.not_to raise_error, input.inspect
        end
        expect(rule.match?("https://editor.levelcode.test/callback.html?%zz")).to be(false)
        expect(rule.match?("https://editor.levelcode.test/callback.html?vscode-reqid=%FF&#{URI.encode_www_form(vscode.except('vscode-reqid'))}")).to be(false)
        expect(rule.match?(nil)).to be(false)
      end

      it "is not talked out of its answer by an invalidly encoded name it is not asking about" do
        expect(rule.match?("#{callback}&%FFx=1")).to be(true)
      end
    end

    describe "the setting" do
      it "is a comma list — origins are trimmed and case-folded, default ports dropped, blanks and repeats dropped" do
        rule = described_class.new(web_origins: " https://Editor.LevelCode.Test ,, http://LOCALHOST:5173, https://editor.levelcode.test:443,https://other.levelcode.test:8443 ")
        expect(rule.web_origins).to eq(%w[https://editor.levelcode.test http://localhost:5173 https://other.levelcode.test:8443])
        expect(rule.ignored_web_origins).to eq([])
        expect(rule.web_enabled?).to be(true)
      end

      it "keeps the order it was given — the first is the one the account page links to" do
        rule = described_class.new(web_origins: "https://b.levelcode.test,https://a.levelcode.test")
        expect(rule.web_origins).to eq(%w[https://b.levelcode.test https://a.levelcode.test])
        expect(rule.web_url).to eq("https://b.levelcode.test")
      end

      it "reports an entry it will not take as written, beside the ones it did" do
        rule = described_class.new(web_origins: "https://editor.levelcode.test, https://*.levelcode.test, http://editor.levelcode.test , https://editor.levelcode.test/app")
        expect(rule.web_origins).to eq(%w[https://editor.levelcode.test])
        expect(rule.ignored_web_origins).to eq(%w[https://*.levelcode.test http://editor.levelcode.test https://editor.levelcode.test/app])
      end

      it "never lets a neighbour's typo cost an entry its place" do
        rule = described_class.new(web_origins: "https://a.levelcode.test, oops, https://b.levelcode.test")
        expect(rule.web_origins).to eq(%w[https://a.levelcode.test https://b.levelcode.test])
        expect(rule.ignored_web_origins).to eq(%w[oops])
      end

      it "is none for an empty or missing list" do
        expect(described_class.new(web_origins: "").web_origins).to eq([])
        expect(described_class.new(web_origins: nil).web_origins).to eq([])
        expect(described_class.new(web_origins: "  ,  ").web_origins).to eq([])
      end

      # Both are read once, at boot: a setting that is not valid text must not stop the server starting.
      it "does not raise for text that is not valid UTF-8" do
        rule = described_class.new(
          extra_schemes: "levelcode-dev,\xFF".dup.force_encoding("UTF-8"),
          web_origins: "https://editor.levelcode.test,\xFFhttps://x.test".dup.force_encoding("UTF-8"),
          web_url: "https://editor.levelcode.test/\xFF".dup.force_encoding("UTF-8")
        )
        expect(rule.schemes).to eq(%w[levelcode atom-plus-plus levelcode-dev])
        expect(rule.ignored.size).to eq(1)
        expect(rule.web_origins).to eq(%w[https://editor.levelcode.test])
        expect(rule.ignored_web_origins.size).to eq(1)
        expect(rule.web_url).to eq("https://editor.levelcode.test")
        expect(rule.ignored_web_url).to be_present
      end

      it "is exactly as the extra-schemes setting is: neither adds to nor reads the other" do
        rule = described_class.new(extra_schemes: "levelcode-dev", web_origins: "levelcode-dev")
        expect(rule.schemes).to eq(%w[levelcode atom-plus-plus levelcode-dev])
        expect(rule.ignored).to eq([])
        expect(rule.web_origins).to eq([])
        expect(rule.ignored_web_origins).to eq(%w[levelcode-dev])
      end
    end

    describe "#web_origin?" do
      it "is an exact member of the list — what a browser sends as Origin" do
        two = described_class.new(web_origins: "https://editor.levelcode.test, http://localhost:5173")
        expect(two.web_origin?("https://editor.levelcode.test")).to be(true)
        expect(two.web_origin?("http://localhost:5173")).to be(true)
      end

      it "is not a pattern, a suffix, a prefix or a case-fold" do
        two = described_class.new(web_origins: "https://editor.levelcode.test")
        [
          "https://EDITOR.levelcode.test", "https://editor.levelcode.test/", "https://editor.levelcode.test:443",
          "https://editor.levelcode.test.evil.test", "https://evil.test/https://editor.levelcode.test",
          "http://editor.levelcode.test", "https://editor.levelcode.test:8443", "null", "", nil, "*",
          "https://editor.levelcode.test ", " https://editor.levelcode.test", "https://editor.levelcode.test\n"
        ].each do |source|
          expect(two.web_origin?(source)).to be(false), source.inspect
        end
      end
    end

    describe "#web_url" do
      def with_url(entry, origins: "https://editor.levelcode.test, https://other.levelcode.test")
        described_class.new(web_origins: origins, web_url: entry)
      end

      it "is the first origin when the setting is not given" do
        expect(with_url("").web_url).to eq("https://editor.levelcode.test")
        expect(with_url(nil).web_url).to eq("https://editor.levelcode.test")
        expect(with_url("  ").web_url).to eq("https://editor.levelcode.test")
        expect(with_url("").ignored_web_url).to be_nil
      end

      it "is the setting, when it is a listed origin and, optionally, a path" do
        expect(with_url("https://other.levelcode.test").web_url).to eq("https://other.levelcode.test")
        expect(with_url("https://other.levelcode.test/").web_url).to eq("https://other.levelcode.test/")
        expect(with_url("https://editor.levelcode.test/app/").web_url).to eq("https://editor.levelcode.test/app/")
        expect(with_url("  HTTPS://Editor.LevelCode.Test:443/App ").web_url).to eq("https://editor.levelcode.test/App")
        expect(with_url("https://other.levelcode.test").ignored_web_url).to be_nil
      end

      it "falls back to the first origin, and says what it did not take" do
        {
          "not an address" => "editor",
          "over http, for a host that is not local" => "http://editor.levelcode.test/",
          "with a query" => "https://editor.levelcode.test/?folder=/work",
          "with a fragment" => "https://editor.levelcode.test/#x",
          "with userinfo" => "https://user@editor.levelcode.test/",
          "a wildcard" => "https://*.levelcode.test/",
          "an origin the server was not told of" => "https://elsewhere.levelcode.test/",
          "a listed host on another port" => "https://editor.levelcode.test:8443/",
          "a javascript address" => "javascript:alert(1)"
        }.each do |what, entry|
          rule = with_url(entry)
          expect(rule.web_url).to eq("https://editor.levelcode.test"), what
          expect(rule.ignored_web_url).to eq(entry), what
        end
      end

      it "is nothing while the web edition is off — and is reported, since it can do nothing" do
        rule = described_class.new(web_origins: "", web_url: "https://editor.levelcode.test/")
        expect(rule.web_url).to be_nil
        expect(rule.ignored_web_url).to eq("https://editor.levelcode.test/")
      end
    end

    describe ".from_env" do
      it "reads both settings from the environment it is given" do
        rule = described_class.from_env(
          "LEVELCODE_WEB_EDITOR_ORIGINS" => "https://editor.levelcode.test,http://localhost:5173",
          "LEVELCODE_WEB_EDITOR_URL" => "http://localhost:5173/app"
        )
        expect(rule.web_origins).to eq(%w[https://editor.levelcode.test http://localhost:5173])
        expect(rule.web_url).to eq("http://localhost:5173/app")
      end

      it "is off when the settings are absent — what production runs with" do
        rule = described_class.from_env({})
        expect(rule.web_enabled?).to be(false)
        expect(rule.web_origins).to eq([])
        expect(rule.web_url).to be_nil
      end

      it "reads the extra schemes and the web origins independently" do
        rule = described_class.from_env("LEVELCODE_WEB_EDITOR_ORIGINS" => "https://editor.levelcode.test")
        expect(rule.schemes).to eq(%w[levelcode atom-plus-plus])
        expect(rule.web_enabled?).to be(true)
      end
    end

    describe ".current" do
      let(:fresh) { Class.new(described_class) }

      it "says so in the log, once, when the origins name something it will not take" do
        allow(fresh).to receive(:from_env).and_return(described_class.new(web_origins: "https://editor.levelcode.test, https://*.levelcode.test, http://x.test"))
        expect(Rails.logger).to receive(:warn).once.with(
          %r{LEVELCODE_WEB_EDITOR_ORIGINS: ignoring "https://\*\.levelcode\.test", "http://x\.test" — a web editor origin looks like https://editor\.example\.com}
        )

        2.times { fresh.current }
      end

      it "says so, once, when the URL is not one it will take" do
        allow(fresh).to receive(:from_env).and_return(described_class.new(web_origins: "https://editor.levelcode.test", web_url: "https://elsewhere.test/"))
        expect(Rails.logger).to receive(:warn).once.with(/LEVELCODE_WEB_EDITOR_URL: ignoring "https:\/\/elsewhere\.test\/"/)

        2.times { fresh.current }
      end

      it "says each thing it did not take, and the schemes beside the origins" do
        allow(fresh).to receive(:from_env).and_return(
          described_class.new(extra_schemes: "https", web_origins: "ftp://x", web_url: "nope")
        )
        messages = []
        allow(Rails.logger).to receive(:warn) { |message| messages << message }

        fresh.current

        expect(messages.size).to eq(3)
        expect(messages[0]).to match(/LEVELCODE_EXTRA_EDITOR_SCHEMES: ignoring "https"/)
        expect(messages[1]).to match(/LEVELCODE_WEB_EDITOR_ORIGINS: ignoring "ftp:\/\/x"/)
        expect(messages[2]).to match(/LEVELCODE_WEB_EDITOR_URL: ignoring "nope"/)
      end

      it "says nothing when every entry was taken" do
        allow(fresh).to receive(:from_env).and_return(
          described_class.new(web_origins: "https://editor.levelcode.test, http://localhost:5173", web_url: "https://editor.levelcode.test/app")
        )
        expect(Rails.logger).not_to receive(:warn)

        fresh.current
      end
    end

    it "is immutable" do
      rule = described_class.new(web_origins: "https://editor.levelcode.test, oops", web_url: "nope")
      expect(rule).to be_frozen
      expect(rule.web_origins).to be_frozen
      expect(rule.ignored_web_origins).to be_frozen
    end
  end
end
