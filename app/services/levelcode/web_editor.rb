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
  # One place has a wildcard, and it is not an address a code is sent to: the origin the editor's
  # extension host runs on (see .extension_host). Everything an extension asks of the API comes from
  # there, and a deployment that isolates the host gives every session an origin of its own.
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
    # `*` as the whole of the leftmost label, then a domain. Nothing else is a wildcard: not a part of a
    # label, not twice, not in the scheme or the port.
    WILDCARD = %r{\A(?<scheme>https?)://\*\.(?<parent>#{HOSTNAME})(?::(?<port>\d{1,5}))?\z}
    # What the editor puts on the one label of an extension host's origin that is the session's own:
    # `v--` and then letters and digits. A wildcard stands for a label like this and for nothing else —
    # a subdomain the same operator uses for another purpose is not an extension host.
    EXTENSION_HOST_LABEL = /\Av--[a-z0-9]{1,63}\z/

    # A wildcard origin: `scheme://*.parent[:port]`, taken apart so that it is compared by part and
    # never by a test on the text of an address. port is nil for the scheme's own.
    Wildcard = Data.define(:scheme, :parent, :port) do
      def to_s
        "#{scheme}://*.#{parent}#{":#{port}" if port}"
      end
    end
    # An origin and, optionally, a path — what the account page links to. No query, no fragment.
    URL = %r{\A(?<origin>[^/?#]+://[^/?#]+)(?<path>/[^?#]*)?\z}
    # Plain path characters only: nothing encoded, so nothing to read twice.
    PATH = %r{\A(?:/[A-Za-z0-9._~-]*)*\z}

    # The origin an entry names, in the one form the list is kept in (lower case, default port
    # dropped) — or nil when the entry is not an origin this server will take.
    def origin(entry)
      found = ORIGIN.match(entry.to_s.scrub.strip.downcase(:ascii))
      return nil unless found

      scheme, host, port = parts_of(found)
      return nil unless scheme
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

    # An entry of the list of origins an extension host runs on: an origin, exactly as .origin takes
    # one (a String), or one wildcard (a Wildcard) —
    #
    #   https://*.ext.example.com[:port]
    #
    # The star is exactly one DNS label, the leftmost, whole. The rest is a domain: at least two
    # labels, so that `*.com` names no one, or `localhost`, for development. It is not an address (an
    # IP has no subdomains) and, over http, it is local. nil when the entry is neither.
    #
    # Not checked, because it cannot be from here: that the parent is a domain the deployment owns and
    # not a public suffix like `co.uk`, under which anyone may register `v--x`.
    def extension_host(entry)
      text = entry.to_s.scrub.strip
      text.include?("*") ? wildcard(text) : origin(text)
    end

    # Does one of `wildcards` stand for `source` — an Origin header as a browser sends it?
    #
    # The address is read the way a browser writes an origin (lower case, no default port, nothing
    # after the port), taken apart, and its parts are compared whole: the scheme, the port, a first
    # label that is the session's own, and EVERYTHING after that label against the entry's domain.
    # Not a suffix test, not a substring test: v--abc.ext.example.com.evil.com, v--abc.evil.ext.example.com
    # and x.v--abc.ext.example.com each fail one of those comparisons.
    def wildcard_origin?(wildcards, source)
      scheme, host, port = canonical_parts(source)
      return false unless scheme

      label, dot, parent = host.partition(".")
      return false if dot.empty? || !label.match?(EXTENSION_HOST_LABEL)

      wildcards.any? { |wildcard| wildcard.scheme == scheme && wildcard.port == port && wildcard.parent == parent }
    end

    # [scheme, host, port] of `source` when it is an origin written the way a browser writes one, or
    # nil. Case is not folded and a default port is not dropped: what a browser sends is canonical, so
    # anything that is not is not from one.
    def canonical_parts(source)
      return nil unless source.is_a?(String) && source.valid_encoding?

      found = ORIGIN.match(source)
      return nil unless found

      scheme, host, port = parts_of(found)
      return nil unless scheme
      return nil unless serialize(scheme, host, port) == source

      [ scheme, host, port ]
    end

    # [scheme, host, port] of a match of ORIGIN, or nil when the host is longer than a name can be or
    # the port is not one. port is nil when none was written.
    def parts_of(found)
      host = found[:host]
      port = found[:port]&.to_i
      return nil if host.length > MAX_HOST
      return nil if port && !(1..65_535).cover?(port)

      [ found[:scheme], host, port ]
    end

    def wildcard(text)
      found = WILDCARD.match(text.downcase(:ascii))
      return nil unless found

      scheme = found[:scheme]
      parent = found[:parent]
      port = found[:port]&.to_i
      return nil if port && !(1..65_535).cover?(port)
      return nil if parent.length > MAX_HOST - 2 # a label and a dot must fit in front of it
      return nil unless wildcard_parent?(parent)
      return nil if scheme == "http" && !local_parent?(parent)

      Wildcard.new(scheme: scheme, parent: parent, port: port == DEFAULT_PORTS[scheme] ? nil : port)
    end

    # A domain something can be a subdomain of: not an address, and either two labels or more (a single
    # label is a top-level domain) or `localhost`.
    def wildcard_parent?(parent)
      return false if parent.match?(NUMERIC_END)

      parent.include?(".") || parent == "localhost"
    end

    def local_parent?(parent)
      parent == "localhost" || parent.end_with?(".localhost")
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
