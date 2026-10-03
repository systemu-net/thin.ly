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
  class EditorCallback
    HOST = "levelcode.levelcode-ai"
    PATH = "/auth/callback"
    # `levelcode` is the shipped editor. `atom-plus-plus` is what a build from before the rename
    # still sends.
    SCHEMES = %w[levelcode atom-plus-plus].freeze

    class << self
      # The rule for this process.
      def current
        @current ||= new
      end
    end

    attr_reader :schemes

    def initialize
      @schemes = SCHEMES
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
