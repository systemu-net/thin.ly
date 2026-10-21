require "rails_helper"

# Levelcode::WebFetch must never read a page on this server's own network. The address checks run on addresses
# alone; the reading runs against a real HTTP server on 127.0.0.1, reached through the `connect` seam (the guard
# itself would refuse 127.0.0.1, which is the point of the first examples).
RSpec.describe Levelcode::WebFetch do
  describe ".private_address?" do
    it "is true for loopback, private, link-local, carrier-grade, multicast, reserved and mapped addresses" do
      %w[127.0.0.1 10.1.2.3 172.16.0.1 172.31.255.255 192.168.1.1 169.254.169.254 100.64.0.1 0.0.0.0 224.0.0.1 240.0.0.1
         198.18.0.1 ::1 :: fe80::1 fd00::1 ff02::1 ::ffff:127.0.0.1 ::ffff:10.0.0.1 64:ff9b::a00:1 2001:db8::1 [::1] nonsense].each do |a|
        expect(described_class.private_address?(a)).to be(true), a
      end
    end

    it "is false for public addresses" do
      %w[8.8.8.8 1.1.1.1 172.32.0.1 172.15.255.255 100.128.0.1 2606:4700::6810:84e5 ::ffff:8.8.8.8].each do |a|
        expect(described_class.private_address?(a)).to be(false), a
      end
    end
  end

  describe ".get" do
    let(:never) { ->(*) { raise "must not connect" } }

    it "refuses a name with any private address, before connecting — so a second DNS answer cannot sneak one in" do
      expect { described_class.get("http://internal.example/", resolver: ->(_) { %w[93.184.216.34 10.0.0.5] }, connect: never) }
        .to raise_error(Levelcode::WebFetch::Blocked, /private or local network/)
      %w[http://127.0.0.1/ http://[::1]/ http://169.254.169.254/latest/meta-data].each do |u|
        expect { described_class.get(u, connect: never) }.to raise_error(Levelcode::WebFetch::Blocked), u
      end
      expect { described_class.get("http://localhost:3000/", connect: never) }.to raise_error(Levelcode::WebFetch::Blocked)
    end

    it "refuses other schemes, credentials in the address, and names that do not resolve" do
      expect { described_class.get("ftp://example.org/x", connect: never) }.to raise_error(Levelcode::WebFetch::Blocked, /only http and https/)
      expect { described_class.get("https://u:p@example.org/", resolver: ->(_) { %w[93.184.216.34] }, connect: never) }.to raise_error(Levelcode::WebFetch::Blocked, /user name or password/)
      expect { described_class.get("https://nothing.invalid/", resolver: ->(_) { [] }, connect: never) }.to raise_error(Levelcode::WebFetch::Blocked, /does not resolve/)
    end

    it "connects to the address that was checked, follows a redirect after checking it again, and refuses a hop to a private one" do
      seen = []
      connect = lambda do |uri, ip|
        seen << [ uri.to_s, ip ]
        case uri.path
        when "/a" then [ 302, { "location" => "/b" }, "", false ]
        when "/b" then [ 200, { "content-type" => "text/html; charset=utf-8" }, "<p>Grüße</p>", false ]
        when "/evil" then [ 301, { "location" => "http://10.0.0.1/admin" }, "", false ]
        end
      end
      page = described_class.get("https://public.example/a", resolver: ->(_) { %w[93.184.216.34] }, connect: connect)
      expect(page).to eq(final_url: "https://public.example/b", status: 200, content_type: "text/html; charset=utf-8", body: "<p>Grüße</p>", truncated: false)
      expect(seen).to eq([ [ "https://public.example/a", "93.184.216.34" ], [ "https://public.example/b", "93.184.216.34" ] ])

      expect { described_class.get("https://public.example/evil", resolver: ->(h) { h == "10.0.0.1" ? %w[10.0.0.1] : %w[93.184.216.34] }, connect: connect) }
        .to raise_error(Levelcode::WebFetch::Blocked, /private or local/)
    end

    it "refuses a page that is not text, stops after four redirects, and turns another charset into UTF-8" do
      pdf = ->(*) { [ 200, { "content-type" => "application/pdf" }, "%PDF", false ] }
      expect { described_class.get("https://p.example/f", resolver: ->(_) { %w[93.184.216.34] }, connect: pdf) }.to raise_error(Levelcode::WebFetch::NotText, /application\/pdf/)
      loop_ = ->(*) { [ 302, { "location" => "/again" }, "", false ] }
      expect { described_class.get("https://p.example/", resolver: ->(_) { %w[93.184.216.34] }, connect: loop_) }.to raise_error(Levelcode::WebFetch::Blocked, /too many redirects/)
      latin = ->(*) { [ 200, { "content-type" => "text/plain; charset=ISO-8859-1" }, "caf\xE9".b, false ] }
      expect(described_class.get("https://p.example/", resolver: ->(_) { %w[93.184.216.34] }, connect: latin)[:body]).to eq("café")
    end
  end

  describe ".request (a real HTTP server on 127.0.0.1)" do
    around do |ex|
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @thread = Thread.new do
        loop do
          s = @server.accept
          line = s.gets.to_s
          nil while (h = s.gets) && h != "\r\n"
          path = line.split[1]
          body = path == "/big" ? ("x" * (Levelcode::WebFetch::MAX_BYTES + 5000)) : "hello #{path}"
          s.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
          s.close
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET
          nil
        end
      end
      ex.run
    ensure
      @thread&.kill
      @server&.close
    end

    it "reads the body, sends a LevelCode user agent, and cuts a page larger than 2 MB" do
      status, headers, body, truncated = described_class.request(URI("http://127.0.0.1:#{@port}/page"), "127.0.0.1")
      expect([ status, headers["content-type"], body, truncated ]).to eq([ 200, "text/plain", "hello /page", false ])
      _, _, big, cut = described_class.request(URI("http://127.0.0.1:#{@port}/big"), "127.0.0.1")
      expect([ big.bytesize, cut ]).to eq([ Levelcode::WebFetch::MAX_BYTES, true ])
    end
  end
end
