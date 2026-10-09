require "rails_helper"

# LevelCode in the browser: the CORS the editor's web edition needs to call the API from its page, and
# nothing more. These run the real Rack::Cors middleware with the real config
# (config/initializers/cors.rb); what is told to the server is only the list of origins, the way
# LEVELCODE_WEB_EDITOR_ORIGINS tells it (Levelcode::EditorCallback, which the middleware asks).
RSpec.describe "LevelCode API CORS for the web editor", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:editor_origin) { "https://editor.levelcode.test" }
  let(:gateway) { "/api/levelcode/v1/ai/chat/completions" }

  def preflight(path, origin:, method: "POST", headers: "authorization,content-type")
    process(
      :options,
      path,
      headers: {
        "HTTP_ORIGIN" => origin,
        "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => method,
        "HTTP_ACCESS_CONTROL_REQUEST_HEADERS" => headers
      }
    )
  end

  def allow_origin = response.headers["Access-Control-Allow-Origin"]
  def allow_methods = response.headers["Access-Control-Allow-Methods"].to_s.split(/,\s*/)
  def vary = response.headers["Vary"].to_s.split(/,\s*/)

  describe "on a server told of the editor's origin" do
    before { with_web_editor(editor_origin) }

    describe "preflight" do
      it "lets the editor's page POST with a Bearer token and a JSON body to the gateway" do
        preflight(gateway, origin: editor_origin)

        expect(response).to have_http_status(:ok)
        expect(allow_origin).to eq(editor_origin)
        expect(allow_methods).to include("POST")
        expect(response.headers["Access-Control-Allow-Headers"].to_s.downcase).to include("authorization")
        expect(response.headers["Access-Control-Allow-Headers"].to_s.downcase).to include("content-type")
        expect(response.headers["Access-Control-Max-Age"]).to eq("600")
      end

      it "never allows credentials: a cookie must not make the answer readable to that page" do
        preflight(gateway, origin: editor_origin)

        expect(response.headers).not_to have_key("Access-Control-Allow-Credentials")
      end

      it "exposes no header — the editor reads the status and the body" do
        preflight(gateway, origin: editor_origin)

        expect(response.headers["Access-Control-Expose-Headers"].to_s).to eq("")
      end

      it "allows only get, post and options" do
        preflight(gateway, origin: editor_origin)

        expect(allow_methods).to contain_exactly("GET", "POST", "OPTIONS")
      end

      %w[/api/levelcode/v1/auth/exchange /api/levelcode/v1/auth/refresh /api/levelcode/v1/auth/web_handoff
         /api/levelcode/v1/ai/chat /api/levelcode/v1/account/models /api/levelcode/v1/account/profile
         /api/levelcode/v1/feedback /api/levelcode/v1/web_editor].each do |path|
        it "answers for #{path}" do
          preflight(path, origin: editor_origin)

          expect(allow_origin).to eq(editor_origin)
        end
      end

      it "allows the headers that make a request non-simple, for a GET with only a Bearer token" do
        preflight("/api/levelcode/v1/account/models", origin: editor_origin, method: "GET", headers: "authorization")

        expect(allow_origin).to eq(editor_origin)
      end

      it "allows accept, which a fetch of an SSE stream may name" do
        preflight(gateway, origin: editor_origin, headers: "authorization,content-type,accept")

        expect(allow_origin).to eq(editor_origin)
      end

      it "says nothing to an origin that is not the editor's" do
        [
          "https://evil.test",
          "https://editor.levelcode.test.evil.test",
          "https://eviledtor.levelcode.test",
          "https://levelcode.test",
          "https://editor.levelcode.test:8443",
          "http://editor.levelcode.test",
          "https://EDITOR.levelcode.test",
          "https://editor.levelcode.test.",
          "https://editor.levelcode.test/",
          "null",
          "file://",
          "*"
        ].each do |origin|
          preflight(gateway, origin: origin)

          expect(allow_origin).to be_nil, origin.inspect
          expect(response.headers.keys.grep(/\Aaccess-control-/i)).to be_empty, origin.inspect
        end
      end

      it "says nothing for a header it does not name — the page's request would be refused by the browser" do
        %w[x-requested-with x-levelcode-service-token cookie x-csrf-token authorization,x-evil].each do |headers|
          preflight(gateway, origin: editor_origin, headers: headers)

          expect(allow_origin).to be_nil, headers
        end
      end

      it "says nothing for a method it does not allow" do
        %w[PUT PATCH DELETE].each do |method|
          preflight(gateway, origin: editor_origin, method: method)

          expect(allow_origin).to be_nil, method
        end
      end
    end

    describe "what the editor's origin is not given" do
      # thin.ly's own app and the account flows: the editor's page runs other people's extensions.
      %w[/api/v1/links /api/v1/user /api/v1/current_user /api/v1/billings /api/v1/track/view
         /ai/auth/verify /ai/authorize_editor /ai/checkout /ai/billing /ai/signout /users/sign_in
         /api/update/darwin-arm64/stable/abc].each do |path|
        it "gets nothing from a preflight for #{path}" do
          preflight(path, origin: editor_origin)

          expect(allow_origin).to be_nil
          expect(response.headers.keys.grep(/\Aaccess-control-/i)).to be_empty
        end
      end

      it "gets nothing on an actual request to thin.ly's API" do
        get "/api/v1/current_user", headers: { "HTTP_ORIGIN" => editor_origin }

        expect(allow_origin).to be_nil
        expect(response.headers.keys.grep(/\Aaccess-control-/i)).to be_empty
      end

      it "gets nothing on an actual request to the account flows" do
        get "/ai/csrf", headers: { "HTTP_ORIGIN" => editor_origin }

        expect(allow_origin).to be_nil
      end

      it "gets nothing on a path that only looks like the API's" do
        %w[/api/levelcode /api/levelcode/v1 /api/levelcode/v1evil /api/levelcode/v2/ai/chat /api/levelcodeX/v1/ai /api/v1/api/levelcode/v1/ai].each do |path|
          preflight(path, origin: editor_origin)

          expect(allow_origin).to be_nil, path
        end
      end
    end

    describe "an actual request" do
      it "to a public endpoint carries the allow-origin header, and no credentials header" do
        get "/api/levelcode/v1/pricing", headers: { "HTTP_ORIGIN" => editor_origin }

        expect(response).to have_http_status(:ok)
        expect(allow_origin).to eq(editor_origin)
        expect(response.headers).not_to have_key("Access-Control-Allow-Credentials")
        expect(vary).to include("Origin")
      end

      it "to the sign-in exchange carries it — the page must be able to read the error as well as the tokens" do
        post "/api/levelcode/v1/auth/exchange",
             params: { code: "nope", verifier: "nope" }.to_json,
             headers: { "HTTP_ORIGIN" => editor_origin, "CONTENT_TYPE" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body).dig("error", "code")).to eq("invalid_code")
        expect(allow_origin).to eq(editor_origin)
      end

      it "that is unauthorised carries it too: the editor keys on the code to refresh or to sign in again" do
        post gateway,
             params: { model: "x", messages: [] }.to_json,
             headers: { "HTTP_ORIGIN" => editor_origin, "CONTENT_TYPE" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
        expect(allow_origin).to eq(editor_origin)
      end

      it "carrying a cookie is no more readable: still no credentials header" do
        get "/api/levelcode/v1/pricing",
            headers: { "HTTP_ORIGIN" => editor_origin, "HTTP_COOKIE" => "_your_app_session=abc" }

        expect(allow_origin).to eq(editor_origin)
        expect(response.headers).not_to have_key("Access-Control-Allow-Credentials")
      end

      it "from another origin carries nothing" do
        post "/api/levelcode/v1/auth/exchange",
             params: { code: "nope" }.to_json,
             headers: { "HTTP_ORIGIN" => "https://evil.test", "CONTENT_TYPE" => "application/json" }

        expect(allow_origin).to be_nil
      end

      it "with no Origin is untouched" do
        get "/api/levelcode/v1/pricing"

        expect(response).to have_http_status(:ok)
        expect(response.headers.keys.grep(/\Aaccess-control-/i)).to be_empty
      end

      # ActionController::Live: the gateway streams SSE. The page reads that stream cross-origin, so the
      # header has to be on the response that starts it, not only on the buffered ones.
      describe "that is streamed (SSE)" do
        around do |example|
          prev = ENV["LEVELCODE_JWT_SECRET"]
          ENV["LEVELCODE_JWT_SECRET"] = "test-levelcode-secret"
          with_fake_redis { example.run }
        ensure
          ENV["LEVELCODE_JWT_SECRET"] = prev
        end

        it "carries the allow-origin header on the stream the gateway answers with" do
          user = create(:user)
          allow(Stripe::Customer).to receive(:create).and_return(Stripe::Customer.construct_from(id: "cus_test"))
          # The action is stood in for: what is under test is the stream going out through the middleware.
          allow_any_instance_of(Api::Levelcode::V1::AiController).to receive(:chat) do |controller|
            controller.response.headers["Content-Type"] = "text/event-stream"
            controller.response.stream.write("data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}\n\n")
            controller.response.stream.write("data: [DONE]\n\n")
            controller.response.stream.close
          end

          post gateway,
               params: { model: "x", stream: true, messages: [] }.to_json,
               headers: { "HTTP_ORIGIN" => editor_origin, "CONTENT_TYPE" => "application/json",
                          "HTTP_AUTHORIZATION" => "Bearer #{Levelcode::EditorToken.mint_access(user)}" }

          expect(response).to have_http_status(:ok)
          expect(response.headers["Content-Type"]).to include("text/event-stream")
          expect(response.body).to include("data: [DONE]")
          expect(allow_origin).to eq(editor_origin)
          expect(response.headers).not_to have_key("Access-Control-Allow-Credentials")
        end
      end
    end

    describe "thin.ly's own origins" do
      # The catch-all block, as it was: not narrowed by the editor's, nor widened.
      %w[https://thin.ly https://www.thin.ly https://app.thin.ly http://localhost:3000].each do |origin|
        it "keep every method and the exposed headers on thin.ly's API — #{origin}" do
          preflight("/api/v1/links", origin: origin, method: "PATCH")

          expect(allow_origin).to eq(origin)
          expect(allow_methods).to include("GET", "PATCH", "PUT", "DELETE", "POST", "OPTIONS")
          expect(response.headers["Access-Control-Expose-Headers"]).to eq("access-token, expiry, token-type, Authorization")
          expect(response.headers["Access-Control-Max-Age"]).to eq("7200")
        end

        it "keep the LevelCode API as they had it — #{origin}" do
          get "/api/levelcode/v1/pricing", headers: { "HTTP_ORIGIN" => origin }

          expect(allow_origin).to eq(origin)
          expect(response.headers["Access-Control-Expose-Headers"]).to eq("access-token, expiry, token-type, Authorization")
        end
      end

      it "are not given the editor's narrower block instead: any header is still allowed to them" do
        preflight(gateway, origin: "https://thin.ly", headers: "authorization,content-type,x-anything")

        expect(allow_origin).to eq("https://thin.ly")
      end

      it "still reach the track beacon from a published page, and only that" do
        preflight("/api/v1/track/view", origin: "https://l381z6.thin.ly", headers: "content-type")
        expect(allow_origin).to eq("https://l381z6.thin.ly")

        preflight(gateway, origin: "https://l381z6.thin.ly")
        expect(allow_origin).to be_nil
      end

      it "do not make the editor's origin theirs" do
        get "/api/levelcode/v1/pricing", headers: { "HTTP_ORIGIN" => "https://thin.ly.evil.test" }

        expect(allow_origin).to be_nil
      end
    end

    it "leaves the health check public to every origin, as it was" do
      get "/up", headers: { "HTTP_ORIGIN" => "https://anything.test" }

      expect(allow_origin).to eq("*")
    end
  end

  describe "on a server that has not been told of one (production)" do
    it "gives the editor's origin nothing, on a preflight or on a request" do
      preflight(gateway, origin: editor_origin)
      expect(allow_origin).to be_nil
      expect(response.headers.keys.grep(/\Aaccess-control-/i)).to be_empty

      get "/api/levelcode/v1/pricing", headers: { "HTTP_ORIGIN" => editor_origin }
      expect(response).to have_http_status(:ok)
      expect(allow_origin).to be_nil
    end

    it "is the rule of a server whose list is empty — however the setting came to be empty" do
      with_web_editor("")
      preflight(gateway, origin: editor_origin)
      expect(allow_origin).to be_nil

      with_web_editor(" , https://*.levelcode.test, http://editor.levelcode.test")
      preflight(gateway, origin: "https://anything.levelcode.test")
      expect(allow_origin).to be_nil
      preflight(gateway, origin: "http://editor.levelcode.test")
      expect(allow_origin).to be_nil
    end

    it "leaves thin.ly's own origins as they were" do
      preflight("/api/v1/links", origin: "https://thin.ly", method: "DELETE")

      expect(allow_origin).to eq("https://thin.ly")
      expect(allow_methods).to include("DELETE")
    end
  end

  describe "with several origins told" do
    it "answers each of them, with its own origin, and no other" do
      with_web_editor("https://editor.levelcode.test, http://localhost:5173")

      preflight(gateway, origin: "https://editor.levelcode.test")
      expect(allow_origin).to eq("https://editor.levelcode.test")

      preflight(gateway, origin: "http://localhost:5173")
      expect(allow_origin).to eq("http://localhost:5173")

      preflight(gateway, origin: "http://localhost:5174")
      expect(allow_origin).to be_nil
    end
  end
end
