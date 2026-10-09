require "rails_helper"

# Whether the editor has a web edition, and where: what the account page asks before it offers
# "Open in browser". The settings behind it — LEVELCODE_WEB_EDITOR_ORIGINS and _URL — are read by
# Levelcode::EditorCallback (specced in spec/services/levelcode/editor_callback_spec.rb); here they are
# told to the server the way that rule would be.
RSpec.describe "Api::Levelcode::V1::WebEditor", type: :request do
  let(:path) { "/api/levelcode/v1/web_editor" }

  describe "GET /api/levelcode/v1/web_editor" do
    context "on a server that has not been told of a web editor (production)" do
      it "says it is off, and has no address to give" do
        get path

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq("enabled" => false, "url" => nil)
      end

      it "says the same however the setting came to be empty or unusable" do
        with_web_editor("  , ftp://x, https://*.levelcode.test", url: "https://editor.levelcode.test/")
        get path

        expect(response.parsed_body).to eq("enabled" => false, "url" => nil)
      end
    end

    context "on a server told of an origin" do
      it "says it is on, and where" do
        with_web_editor("https://editor.levelcode.test")
        get path

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq("enabled" => true, "url" => "https://editor.levelcode.test")
      end

      it "gives the first origin when there are several" do
        with_web_editor("https://editor.levelcode.test, http://localhost:5173")
        get path

        expect(response.parsed_body).to eq("enabled" => true, "url" => "https://editor.levelcode.test")
      end

      it "gives the URL the setting names, when it is one of the origins and, optionally, a path" do
        with_web_editor("https://editor.levelcode.test, https://other.levelcode.test", url: "https://other.levelcode.test/app/")
        get path

        expect(response.parsed_body).to eq("enabled" => true, "url" => "https://other.levelcode.test/app/")
      end

      it "gives the origin as the list writes it: case-folded, default port dropped" do
        with_web_editor(" HTTPS://Editor.LevelCode.Test:443 ")
        get path

        expect(response.parsed_body["url"]).to eq("https://editor.levelcode.test")
      end

      it "gives a local development editor over http" do
        with_web_editor("http://localhost:5173")
        get path

        expect(response.parsed_body).to eq("enabled" => true, "url" => "http://localhost:5173")
      end

      it "ignores a URL that is not usable, and gives the first origin instead" do
        [
          "https://elsewhere.test/",                     # not an origin the server was told of
          "http://editor.levelcode.test/",               # http, for a host that is not local
          "https://editor.levelcode.test/?folder=/work", # a query
          "https://editor.levelcode.test/#x",            # a fragment
          "https://user@editor.levelcode.test/",         # userinfo
          "javascript:alert(1)",
          "not a url"
        ].each do |url|
          with_web_editor("https://editor.levelcode.test", url: url)
          get path

          expect(response.parsed_body).to eq("enabled" => true, "url" => "https://editor.levelcode.test"), url
        end
      end

      it "never gives an address the server would not take a sign-in from" do
        with_web_editor("https://editor.levelcode.test", url: "https://evil.test/callback.html")
        get path

        expect(response.parsed_body["url"]).not_to include("evil.test")
      end
    end

    describe "the response" do
      it "is public: no token, no session, and no cookie set" do
        with_web_editor("https://editor.levelcode.test")
        get path

        expect(response).to have_http_status(:ok)
        expect(response.headers["Set-Cookie"]).to be_nil
      end

      it "may be held by a shared cache for five minutes" do
        get path

        cache_control = response.headers["Cache-Control"].to_s
        expect(cache_control).to include("public")
        expect(cache_control).to include("max-age=300")
        expect(cache_control).not_to include("private")
        expect(cache_control).not_to include("no-store")
      end

      it "is JSON with those two keys and no others" do
        with_web_editor("https://editor.levelcode.test")
        get path

        expect(response.media_type).to eq("application/json")
        expect(response.parsed_body.keys).to contain_exactly("enabled", "url")
      end

      it "is the same for a caller with a token as for one without — nothing in it is theirs" do
        with_web_editor("https://editor.levelcode.test")
        get path
        anonymous = response.body

        get path, headers: { "Authorization" => "Bearer not-a-token" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(anonymous)
      end

      it "is answered to GET only" do
        post path

        expect(response).not_to have_http_status(:ok)
      end
    end
  end
end
