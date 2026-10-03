# frozen_string_literal: true

module Levelcode
  # The one address a sign-in may hand its one-time code to: the editor's own deep link.
  #
  # It has three parts and only one of them varies. The host is the extension id
  # (<publisher>.<name>) and the path is its auth route — both exact. The scheme is the editor
  # BUILD's, its product urlProtocol, so it is a short list rather than a single value.
  #
  # Everything else is refused, because whatever passes gets a one-time code appended to it: a wider
  # rule here is an open redirect that carries a credential. A query is allowed — the editor adds
  # ?windowId=N so the callback reaches the window that asked — and is the caller's to preserve.
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

    class << self
      # The rule for this process, read from the environment once.
      def current
        @current ||= from_env.tap { |rule| warn_about(rule.ignored) }
      end

      def from_env(env = ENV)
        new(extra_schemes: env.fetch(ENV_KEY, ""))
      end

      private

      # A typo in the setting is otherwise invisible: the entry is dropped, and the only symptom is
      # the sign-in it was meant to allow going to the web account instead.
      def warn_about(ignored)
        return if ignored.empty?

        Rails.logger.warn("[levelcode] #{ENV_KEY}: ignoring #{ignored.map(&:inspect).join(', ')} — " \
                          "an extra editor scheme looks like levelcode-dev")
      end
    end

    # schemes: every scheme accepted — the shipped ones, then the extra ones that were usable.
    # ignored: entries of the setting that were not, as written.
    attr_reader :schemes, :ignored

    # extra_schemes: a comma list — entries are trimmed and case-folded, blanks and repeats dropped.
    # A shipped scheme named again is neither added nor reported: it is taken already.
    def initialize(extra_schemes: "")
      entries = extra_schemes.to_s.split(",").map(&:strip).reject { |entry| entry.empty? || SCHEMES.include?(entry.downcase) }
      usable, ignored = entries.partition { |entry| entry.downcase.match?(EXTRA_SCHEME) }
      @schemes = (SCHEMES + usable.map(&:downcase)).uniq.freeze
      @ignored = ignored.freeze
      freeze
    end

    # Is `address` — a URI or a string — the editor's callback? Never raises: an address that does
    # not parse is not the editor's.
    def match?(address)
      uri = URI.parse(address.to_s)
      schemes.include?(uri.scheme) && uri.host == HOST && uri.path == PATH
    rescue URI::InvalidURIError
      false
    end
  end
end
