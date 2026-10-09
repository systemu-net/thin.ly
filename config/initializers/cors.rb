# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  # Health check endpoint - unrestricted for ELB health checks
  allow do
    origins "*"
    resource "/up",
      headers: :any,
      methods: [ :get, :head, :options ]
  end

  allow do
    origins(
      "http://localhost:4000",
      "http://localhost:3000",
      ENV["DEV_HOST"],
      "https://thin.ly",
      "https://www.thin.ly",
      "https://app.thin.ly",
      "https://thinly.ngrok.app",
      /.*\.elasticbeanstalk\.com$/ # Allow EB URLs
    )
    resource(
      "*",
      headers: :any,
      expose: [ "access-token", "expiry", "token-type", "Authorization" ],
      methods: [ :get, :patch, :put, :delete, :post, :options, :show ]
    )
  end

  # Published link-in-bio pages are served from per-user subdomains
  # (e.g. https://john.thin.ly). They are untrusted/public origins, so rather
  # than adding them to the catch-all above they may only reach the analytics
  # tracking endpoints. Without this, the browser's CORS preflight blocks the
  # page-view beacon and no views are recorded.
  allow do
    origins(%r{\Ahttps://[a-z0-9_-]+\.thin\.ly\z}i)
    resource(
      "/api/v1/track/*",
      headers: :any,
      methods: [ :post, :options ]
    )
  end

  # LevelCode in the browser. The editor's web edition is a static page on an origin of its own
  # (LEVELCODE_WEB_EDITOR_ORIGINS, see Levelcode::EditorCallback) and its extension calls the
  # LevelCode API from that page: the sign-in exchange and refresh, the account reads and the metered
  # gateway, each with `Authorization: Bearer`.
  #
  # A block of its own, NOT the catch-all above. That one is thin.ly's app; an editor origin is a
  # page that runs other people's extensions, and gets the LevelCode API and nothing else — not
  # /api/v1/*, not the /ai account flows.
  #
  # No credentials. The editor authenticates with the Bearer header alone, so the browser has no
  # reason to send a cookie and must never be told it may: without Access-Control-Allow-Credentials a
  # page on that origin cannot read an answer that the visitor's account session authorised.
  #
  # Nothing is exposed: the editor reads the status and the body (the SSE stream included) and no
  # header.
  #
  # The origins are the callback rule's own list — one parser, so this and the sign-in redirect
  # cannot disagree about which origin is the editor's — asked per request, because an initializer
  # cannot autoload the app's constants. The rule reads the environment once per process (and is
  # read at boot, below, so a typo in the setting is in the boot log rather than found by the first
  # sign-in): a change to the setting needs a restart. Unset, the list is empty and this never matches.
  #
  # Where the extension host is isolated (LEVELCODE_WEB_EXTENSION_HOST_ORIGINS) every extension's call
  # comes from an origin of its own, https://v--<hash>.ext.example.com, which is not the editor's: it
  # is let in here, by parts, and nowhere else. The same grant, the same headers, and still no
  # credentials.
  allow do
    origins { |source, _env| Levelcode::EditorCallback.current.web_cors_origin?(source) }
    # A pattern, not "/api/levelcode/v1/*": Rack::Cors makes the slash before `*` optional, which would
    # also take /api/levelcode/v1evil. The slash is part of the namespace.
    resource(
      %r{\A/api/levelcode/v1/},
      headers: %w[authorization content-type accept],
      methods: %i[get post options],
      max_age: 600,
      credentials: false
    )
  end
end

Rails.application.config.after_initialize { Levelcode::EditorCallback.current }
