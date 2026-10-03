# frozen_string_literal: true

module Levelcode
  # Which hosts serve the LevelCode Cloud account app, and where it canonically lives.
  #
  # One Rails app answers for two brands: thin.ly, the link shortener, and LevelCode Cloud, the account
  # app (levelcode.html shell) under /ai. This is the one answer to "which brand is this host?". The
  # route constraint that keeps the 7-char shortcode lookup off LevelCode hosts and StaticController#ui
  # both ask it, so routing and dispatch cannot disagree about a host.
  #
  # Both settings are ENV-overridable so a staging or tunnel host (ngrok, a preview deploy) can serve
  # the account app:
  #
  #   LEVELCODE_HOSTS   comma list of hosts that serve the account app instead of the shortener SPA
  #   LEVELCODE_ORIGIN  the canonical origin any /ai request on another host is bounced to
  #
  # Set them TOGETHER. Overriding the origin alone points the bounce at a host that is still not a
  # LevelCode host, and /ai would 301 to itself forever; #origin? is how StaticController#ui notices
  # that and renders instead of looping.
  class Hosts
    DEFAULT_HOSTS = "levelcode.ai,www.levelcode.ai"
    DEFAULT_ORIGIN = "https://levelcode.ai"

    class << self
      # The policy for this process, read from the environment once.
      def current
        @current ||= from_env
      end

      def from_env(env = ENV)
        new(
          hosts: env.fetch("LEVELCODE_HOSTS", DEFAULT_HOSTS),
          origin: env.fetch("LEVELCODE_ORIGIN", DEFAULT_ORIGIN)
        )
      end
    end

    attr_reader :hosts, :origin

    # hosts:  a comma list — entries are trimmed and case-folded, blanks dropped.
    # origin: a URL. Only its host is ever compared; the string itself is the redirect target.
    def initialize(hosts:, origin:)
      @hosts = hosts.to_s.split(",").map { |h| h.strip.downcase }.reject(&:empty?).freeze
      @origin = origin.to_s.freeze
      @origin_host = host_of(@origin)
      freeze
    end

    # Does `host` serve the account app? Case is folded here because Rack hands the Host header through
    # exactly as the client sent it (only the port is stripped) — `LevelCode.AI` is a LevelCode host.
    def include?(host)
      hosts.include?(host.to_s.downcase)
    end

    # Is `host` the canonical origin's own host — i.e. would bouncing it to #origin target itself?
    def origin?(host)
      !@origin_host.nil? && @origin_host.casecmp?(host.to_s) == true
    end

    private

    # nil when the origin cannot be parsed as a URL, which then matches no host.
    def host_of(url)
      URI.parse(url).host.to_s
    rescue URI::InvalidURIError
      nil
    end
  end
end
