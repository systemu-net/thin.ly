# frozen_string_literal: true

require "ipaddr"

module Levelcode
  # What an address of the editor's web edition looks like — the grammar, and only that.
  #
  # The web edition is the editor built as a static page and served from an origin of its own. Three
  # things need that origin and must agree on what one is: the rule for where a sign-in code may be
  # sent (Levelcode::EditorCallback), the CORS rule that lets the page call the API
  # (config/initializers/cors.rb) and the endpoint that tells the account page where the editor is
  # (Api::Levelcode::V1::WebEditorController). All three ask EditorCallback, which asks this, so there
  # is one reading of the settings and no second one to drift.
  #
  # An origin is `scheme://host[:port]` and nothing else — no path, query, fragment or userinfo, and
  # no wildcard. The wildcard is the one a deployment is tempted to write (`https://*.levelcode.ai`)
  # and the one that cannot be allowed: the sign-in code is posted to whatever matches, so every host
  # a wildcard names is a place that code can be sent.
  #
  # The scheme is https. http is for local development only: localhost, 127.0.0.1, [::1] and
  # *.localhost, which a browser treats as a secure context and which cannot be reached from another
  # machine. Anything else over http would send the code in the clear.
  #
  # Pure: no ENV and no logging here — the caller decides what an unusable entry costs.
  module WebEditor
    module_function

    SCHEMES = %w[https http].freeze
    DEFAULT_PORTS = { "https" => 443, "http" => 80 }.freeze

    # A DNS name: dot-separated labels of letters, digits and inner hyphens. No trailing dot (a
    # different origin to a browser, and never what a page's own address is), no empty label, no `*`.
    # Lower case only — entries are case-folded before they are read.
    LABEL = "[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
    HOSTNAME = "(?:#{LABEL}\\.)*#{LABEL}"
    IPV6 = "\\[[0-9a-f:.]+\\]"
    MAX_HOST = 253
    # A host that ends in a number is an IPv4 address to a browser, however it is spelled: `1.2.3` is
    # 1.2.0.3 and `0x7f.1` is 127.0.0.1. Only the canonical dotted quad is taken — written any other
    # way it would never be the origin a browser sends.
    NUMERIC_END = /(?:\A|\.)(?:\d+|0x\h*)\z/
    IPV4 = /\A(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?:\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}\z/

    ORIGIN = %r{\A(?<scheme>https?)://(?<host>#{HOSTNAME}|#{IPV6})(?::(?<port>\d{1,5}))?\z}
    # An origin and, optionally, a path — what the account page links to. No query, no fragment.
    URL = %r{\A(?<origin>[^/?#]+://[^/?#]+)(?<path>/[^?#]*)?\z}
    # Plain path characters only: nothing encoded, so nothing to read twice.
    PATH = %r{\A(?:/[A-Za-z0-9._~-]*)*\z}

    # The origin an entry names, in the one form the list is kept in (lower case, default port
    # dropped) — or nil when the entry is not an origin this server will take.
    def origin(entry)
      found = ORIGIN.match(entry.to_s.scrub.strip.downcase(:ascii))
      return nil unless found

      scheme = found[:scheme]
      host = found[:host]
      port = found[:port]&.to_i
      return nil if host.length > MAX_HOST
      return nil if port && !(1..65_535).cover?(port)
      return nil unless address_or_name?(host)
      return nil if scheme == "http" && !local?(host)

      serialize(scheme, host, port)
    end

    # [origin, path] for an entry that is an origin with an optional path, or nil.
    def parse_url(entry)
      found = URL.match(entry.to_s.scrub.strip)
      return nil unless found

      origin = origin(found[:origin])
      path = found[:path].to_s
      return nil unless origin && PATH.match?(path)

      [ origin, path ]
    end

    # The origin of an address a URI parsed, in the list's own form. Not validated — what is not on
    # the list is not found there.
    def origin_of(uri)
      serialize(uri.scheme, uri.host, uri.port)
    end

    def local?(host)
      %w[localhost 127.0.0.1 [::1]].include?(host) || host.end_with?(".localhost")
    end

    # A name, or an address that is one as written: [::1] must be IPv6, and a host that ends in a
    # number must be a whole dotted quad.
    def address_or_name?(host)
      return ipv6?(host[1..-2]) if host.start_with?("[")

      !host.match?(NUMERIC_END) || host.match?(IPV4)
    end

    def ipv6?(text)
      IPAddr.new(text).ipv6?
    rescue IPAddr::Error
      false
    end

    def serialize(scheme, host, port)
      suffix = port.nil? || port == DEFAULT_PORTS[scheme] ? "" : ":#{port}"
      "#{scheme}://#{host}#{suffix}"
    end
  end
end
