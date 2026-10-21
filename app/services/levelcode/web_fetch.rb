# frozen_string_literal: true

require "net/http"
require "ipaddr"
require "resolv"

module Levelcode
  # Reads a web page for the editor's agent (its `web_fetch` tool, from LevelCode in the browser, where a tab cannot
  # read another site itself; levelcode docs/WEB-SEARCH.md).
  #
  # This server must never become a way into its own network: every address a name resolves to is checked, a name
  # with any private, loopback, link-local or otherwise local address is refused, and the connection goes to the
  # address that was checked (Net::HTTP#ipaddr=), so a second DNS answer cannot swap in another. Every redirect is
  # checked the same way. Only text comes back, at most 2 MB of it.
  module WebFetch
    module_function

    class Blocked < StandardError; end
    class NotText < StandardError; end

    MAX_BYTES = 2 * 1024 * 1024
    MAX_REDIRECTS = 4
    OPEN_TIMEOUT = 4
    READ_TIMEOUT = 8
    USER_AGENT = "Mozilla/5.0 (compatible; LevelCode/1.4; +https://levelcode.ai)"
    TEXTUAL = %r{\A(text/|application/(xhtml\+xml|xml|json|ld\+json|rss\+xml|atom\+xml|javascript))}i

    BLOCKED = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24
      192.88.99.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
      ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8 64:ff9b::/96 2001:db8::/32
    ].map { |c| IPAddr.new(c) }.freeze

    # True for anything that is not the public internet (and for anything that does not parse as an address).
    def private_address?(ip)
      addr = IPAddr.new(ip.to_s.delete_prefix("[").delete_suffix("]").sub(/%.*\z/, ""))
      addr = addr.native if addr.ipv6? && addr.ipv4_mapped?
      BLOCKED.any? { |r| r.family == addr.family && r.include?(addr) }
    rescue IPAddr::Error, ArgumentError
      true
    end

    def resolve(host)
      return [ host ] if host.match?(Resolv::IPv4::Regex) || host.match?(Resolv::IPv6::Regex)

      Resolv.getaddresses(host).uniq
    end

    # { final_url:, status:, content_type:, body:, truncated: }. Raises Blocked, NotText, or a network error.
    # `resolver` and `connect` are the seams the specs replace.
    def get(url, resolver: method(:resolve), connect: method(:request))
      current = url.to_s
      (MAX_REDIRECTS + 1).times do
        uri = URI.parse(current)
        raise Blocked, "only http and https pages can be opened" unless %w[http https].include?(uri.scheme) && uri.host.present?
        raise Blocked, "addresses with a user name or password are not opened" if uri.userinfo.present?

        host = uri.host.delete_prefix("[").delete_suffix("]")
        addresses = resolver.call(host)
        raise Blocked, "#{host} does not resolve" if addresses.empty?
        raise Blocked, "#{host} is on a private or local network; only public pages are opened" if addresses.any? { |a| private_address?(a) }

        status, headers, body, truncated = connect.call(uri, addresses.first)
        if (300..399).cover?(status) && headers["location"].present?
          current = URI.join(current, headers["location"]).to_s
          next
        end
        type = headers["content-type"].to_s
        raise NotText, "#{type.split(';').first.presence || 'unknown type'} is not a text page" if type.present? && !type.match?(TEXTUAL)

        return { final_url: current, status: status, content_type: type, body: utf8(body, type), truncated: truncated }
      end
      raise Blocked, "too many redirects"
    end

    class TooLarge < StandardError; end

    # One GET to `ip`, with the name kept for the Host header and TLS. Answers [status, headers, body, truncated].
    def request(uri, ip)
      http = Net::HTTP.new(uri.host, uri.port)
      http.ipaddr = ip
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      req = Net::HTTP::Get.new(uri.request_uri)
      req["User-Agent"] = USER_AGENT
      req["Accept"] = "text/html,application/xhtml+xml,text/plain;q=0.9,application/json;q=0.8,*/*;q=0.5"
      status = 0
      headers = {}
      body = +""
      truncated = false
      begin
        http.start do
          http.request(req) do |res|
            status = res.code.to_i
            headers = res.to_hash.transform_values { |v| Array(v).join(", ") }
            next if (300..399).cover?(status)

            res.read_body do |chunk|
              body << chunk
              raise TooLarge if body.bytesize > MAX_BYTES
            end
          end
        end
      rescue TooLarge
        body = body.byteslice(0, MAX_BYTES)
        truncated = true
      end
      [ status, headers, body, truncated ]
    end

    def utf8(body, content_type)
      charset = content_type[/charset\s*=\s*"?([\w.:-]+)/i, 1] || "UTF-8"
      enc = Encoding.find(charset) rescue Encoding::UTF_8
      body.to_s.dup.force_encoding(enc).encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�")
    end
  end
end
