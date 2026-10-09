# frozen_string_literal: true

module Levelcode
  # The one address a sign-in may hand its one-time code to: the editor's own callback.
  #
  # There are two shapes of it, and each is exact.
  #
  # The desktop editor's deep link has three parts and only one of them varies. The host is the
  # extension id (<publisher>.<name>) and the path is its auth route — both exact. The scheme is the
  # editor BUILD's, its product urlProtocol, so it is a short list rather than a single value.
  #
  # The web editor (see below) cannot be reached by a custom scheme. It is a page on an origin of its
  # own, and the callback is that page's /callback.html carrying the deep link it stands for:
  #
  #   https://<origin>/callback.html?vscode-reqid=N&vscode-scheme=levelcode
  #     &vscode-authority=levelcode.levelcode-ai&vscode-path=%2Fauth%2Fcallback
  #
  # Everything else is refused, because whatever passes gets a one-time code appended to it: a wider
  # rule here is an open redirect that carries a credential. A query is allowed on the deep link — the
  # editor adds ?windowId=N so the callback reaches the window that asked — and is the caller's to
  # preserve.
  #
  # Levelcode::WebController (the /ai flows) and the API's AuthController both ask this, so the two
  # gates cannot disagree about what an editor is.
  #
  # An editor run from source has its own scheme, `levelcode-dev`: with the shipped one, macOS hands
  # the callback to the installed app instead of the editor that asked. No server takes it unless
  # told to:
  #
  #   LEVELCODE_EXTRA_EDITOR_SCHEMES   comma list of further schemes to accept, e.g. `levelcode-dev`
  #
  # Unset — production — the list is the shipped schemes and nothing else. Set it on the server a
  # development editor signs in to, beside LEVELCODE_HOSTS (Levelcode::Hosts). When a development
  # editor's sign-in ends on the account page in the browser and the editor hears nothing, this is
  # the setting that is missing.
  #
  # The web edition of the editor — the same editor built as a static page and served from an origin
  # of its own — is told about by two settings:
  #
  #   LEVELCODE_WEB_EDITOR_ORIGINS   comma list of the origins it is served from, exactly, e.g.
  #                                  `https://editor.levelcode.ai`
  #   LEVELCODE_WEB_EDITOR_URL       where the account page links to it: one of those origins and,
  #                                  optionally, a path. The first origin when unset.
  #
  # Unset — production, until the web editor ships — the feature is OFF: no web address is accepted,
  # CORS adds nothing and the account page is told there is no web editor. The rule is exactly what
  # it was. Set both on every environment whose account site should hand sign-ins to a web editor,
  # and restart: they are read once per process, with the rest of this.
  #
  # An origin is `scheme://host[:port]` and nothing more — no path, no query, no wildcard
  # (Levelcode::WebEditor has the grammar). It is https; http is accepted only for localhost,
  # 127.0.0.1, [::1] and *.localhost, for development. The list is CORS's as well: exactly these
  # origins may call the LevelCode API from a page (config/initializers/cors.rb). When a web editor's
  # sign-in ends on the account page, or its page cannot reach the API, its origin is the setting
  # that is missing.
  class EditorCallback
    HOST = "levelcode.levelcode-ai"
    PATH = "/auth/callback"
    # `levelcode` is the shipped editor. `atom-plus-plus` is what a build from before the rename
    # still sends.
    SCHEMES = %w[levelcode atom-plus-plus].freeze
    # What the setting may add: a LevelCode build's scheme, `levelcode-<variant>`, and nothing else.
    # The code is appended to whatever this lets through and the browser is sent there, so a list
    # that could be talked into `https` would post the code to a web host, and one that took
    # `javascript` would run script on the account page. Saying what an entry must look like closes
    # both without a list of schemes to forbid.
    EXTRA_SCHEME = /\Alevelcode-[a-z0-9]+(?:[.-][a-z0-9]+)*\z/
    ENV_KEY = "LEVELCODE_EXTRA_EDITOR_SCHEMES"
    WEB_ORIGINS_KEY = "LEVELCODE_WEB_EDITOR_ORIGINS"
    WEB_URL_KEY = "LEVELCODE_WEB_EDITOR_URL"

    # The page the web editor's callback lands on. The editor builds its callback from the address
    # it is running at — location.href with this path and the vscode-* parameters — so the path is
    # the web build's callbackRoute, and fixed.
    WEB_PATH = "/callback.html"
    WEB_PARAM = "vscode-"
    # The page's request counter: a small integer, one per sign-in it has started.
    WEB_REQID = /\A\d{1,9}\z/
    # callback.html merges `vscode-query` into the query it hands the extension, and a name there
    # REPLACES the top-level parameter of the same name. One naming `code` would therefore displace
    # the one-time code this server appends. Only plain pairs are taken, so nothing in it can be
    # read twice into something else, and `code` is not among them.
    WEB_QUERY = /\A[A-Za-z0-9_.~-]+=[A-Za-z0-9_.~-]*(?:&[A-Za-z0-9_.~-]+=[A-Za-z0-9_.~-]*)*\z/

    class << self
      # The rule for this process, read from the environment once.
      def current
        @current ||= from_env.tap { |rule| warn_about(rule) }
      end

      def from_env(env = ENV)
        new(
          extra_schemes: env.fetch(ENV_KEY, ""),
          web_origins: env.fetch(WEB_ORIGINS_KEY, ""),
          web_url: env.fetch(WEB_URL_KEY, "")
        )
      end

      private

      # A typo in a setting is otherwise invisible: the entry is dropped, and the only symptom is
      # the sign-in it was meant to allow going to the web account instead.
      def warn_about(rule)
        unless rule.ignored.empty?
          Rails.logger.warn("[levelcode] #{ENV_KEY}: ignoring #{rule.ignored.map(&:inspect).join(', ')} — " \
                            "an extra editor scheme looks like levelcode-dev")
        end

        unless rule.ignored_web_origins.empty?
          Rails.logger.warn("[levelcode] #{WEB_ORIGINS_KEY}: ignoring #{rule.ignored_web_origins.map(&:inspect).join(', ')} — " \
                            "a web editor origin looks like https://editor.example.com: scheme://host[:port] and " \
                            "nothing after it, https (http only for localhost)")
        end

        return if rule.ignored_web_url.nil?

        Rails.logger.warn("[levelcode] #{WEB_URL_KEY}: ignoring #{rule.ignored_web_url.inspect} — " \
                          "the web editor's URL is one of the origins in #{WEB_ORIGINS_KEY} and, optionally, a path")
      end
    end

    # schemes: every scheme accepted — the shipped ones, then the extra ones that were usable.
    # ignored: entries of the setting that were not, as written.
    attr_reader :schemes, :ignored
    # web_origins: the origins a web editor is served from, in the order given — the same list
    #   that CORS reads. Empty means the web edition is off.
    # web_url: where the account page links to it; the first origin unless the setting named one
    #   of them. nil while the web edition is off.
    # ignored_web_origins / ignored_web_url: what the settings said that was not taken, as written.
    attr_reader :web_origins, :web_url, :ignored_web_origins, :ignored_web_url

    # extra_schemes: a comma list — entries are trimmed and case-folded, blanks and repeats dropped.
    # A shipped scheme named again is neither added nor reported: it is taken already.
    #
    # web_origins: a comma list of origins — trimmed and case-folded, default ports dropped, blanks
    # and repeats dropped. An entry that is not an origin this server takes is dropped and reported.
    #
    # web_url: one URL, or blank. Taken only when it is a listed origin with an optional path.
    def initialize(extra_schemes: "", web_origins: "", web_url: "")
      # scrub: a setting is read once, at boot — text that is not valid UTF-8 must come out as an entry
      # that is not taken, not as an exception that stops the server starting.
      entries = extra_schemes.to_s.scrub.split(",").map(&:strip).reject { |entry| entry.empty? || SCHEMES.include?(entry.downcase) }
      usable, ignored = entries.partition { |entry| entry.downcase.match?(EXTRA_SCHEME) }
      @schemes = (SCHEMES + usable.map(&:downcase)).uniq.freeze
      @ignored = ignored.freeze

      @web_origins, @ignored_web_origins = read_web_origins(web_origins)
      @web_url, @ignored_web_url = read_web_url(web_url, @web_origins)
      freeze
    end

    # Is the web edition on — is there an origin a sign-in code may be sent to?
    def web_enabled?
      !web_origins.empty?
    end

    # Is `source` — an Origin header, as a browser serializes it — one of the web editor's origins?
    # An exact member of the list: no pattern, no suffix, no case-folding.
    def web_origin?(source)
      web_origins.include?(source)
    end

    # Is `address` — a URI or a string — the editor's callback? Never raises: an address that does
    # not parse is not the editor's.
    def match?(address)
      uri = URI.parse(address.to_s)
      deep_link?(uri) || web_callback?(uri)
    rescue URI::InvalidURIError, ArgumentError
      false
    end

    private

    def deep_link?(uri)
      schemes.include?(uri.scheme) && uri.host == HOST && uri.path == PATH
    end

    # The web editor's callback: its page, on one of its origins, saying it stands for the deep link.
    #
    # Each test is the one that keeps a code from going somewhere it should not:
    #   - the ORIGIN is on the list, compared whole — a look-alike host, another port, http for an
    #     https origin, a host with userinfo in front of it, a trailing dot: none of them is listed.
    #   - the PATH is exactly the callback page. The code is appended to the query, so the page is
    #     what receives it.
    #   - the page is told to hand the code to THIS extension (authority + path) and no other: it
    #     dispatches whatever it is told to, to whichever extension registered that address.
    #   - no userinfo and no fragment: nothing in the address that is not the page and its query.
    #
    # Parameters are read as the page reads them — `&`-separated, percent-decoded once — and a
    # vscode-* name given twice is refused: the page takes the first, and a reader that took the
    # last would see a different address than the one that passed.
    def web_callback?(uri)
      return false unless web_enabled?
      return false unless WebEditor::SCHEMES.include?(uri.scheme)
      return false unless uri.userinfo.nil? && uri.fragment.nil? && uri.path == WEB_PATH
      return false unless web_origin?(WebEditor.origin_of(uri))

      web_parameters?(URI.decode_www_form(uri.query.to_s))
    end

    def web_parameters?(pairs)
      vscode = pairs.select { |name, _| name.start_with?(WEB_PARAM) }
      return false unless vscode.map(&:first).uniq.size == vscode.size

      given = vscode.to_h
      given["vscode-authority"] == HOST &&
        given["vscode-path"] == PATH &&
        schemes.include?(given["vscode-scheme"]) &&
        web_reqid?(given["vscode-reqid"]) &&
        web_query?(given["vscode-query"])
    end

    def web_reqid?(value)
      value.is_a?(String) && value.valid_encoding? && value.match?(WEB_REQID)
    end

    # Absent is fine — the editor's own callback has none.
    def web_query?(value)
      return true if value.nil?

      value.valid_encoding? && value.match?(WEB_QUERY) &&
        URI.decode_www_form(value).none? { |name, _| name == "code" }
    end

    def read_web_origins(list)
      origins = []
      ignored = []
      list.to_s.scrub.split(",").map(&:strip).reject(&:empty?).each do |entry|
        origin = WebEditor.origin(entry)
        origin ? origins << origin : ignored << entry
      end
      [ origins.uniq.freeze, ignored.freeze ]
    end

    # [url, ignored]. Taken when it is an origin on the list plus an optional path; otherwise the
    # first origin stands in and the entry is reported. nil while there is no origin at all: a URL
    # the server would not take sign-ins from is not one to send anyone to.
    def read_web_url(entry, origins)
      entry = entry.to_s.scrub.strip
      return [ origins.first, nil ] if entry.empty?

      origin, path = WebEditor.parse_url(entry)
      return [ "#{origin}#{path}", nil ] if origin && origins.include?(origin)

      [ origins.first, entry ]
    end
  end
end
