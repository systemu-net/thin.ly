require "rails_helper"

RSpec.describe UserMailer, type: :mailer do
  describe "created" do
    let(:stripe_helper) { StripeMock.create_test_helper }
    before { StripeMock.start }
    after { StripeMock.stop }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("NOTIFICATION_EMAIL").and_return("test@example.com")
      allow(ENV).to receive(:[]).with("LEVELCODE_MAIL_FROM").and_return(nil)
    end

    def attribution(source, handle)
      { "source" => source, "params" => { source => handle }, "landing" => "/ai" }
    end

    context "an organic signup" do
      let(:user) { create(:user) }
      let(:mail) { UserMailer.created(user) }

      it "renders LevelCode-branded headers" do
        expect(mail.subject).to eq("New LevelCode signup: #{user.email}")
        expect(mail.to).to eq([ "test@example.com" ])
      end

      it "says the signup was organic and carries no thin.ly branding" do
        body = mail.body.encoded
        expect(body).to match(user.email)
        expect(body).to match(/Organic/)
        expect(body).to match("levelcode.ai")
        expect(body).not_to match(/Smart URL Shortener/)
      end
    end

    context "a referred signup" do
      let(:user) { create(:user, signup_attribution: attribution("linkedin", "anastasia")) }
      let(:mail) { UserMailer.created(user) }

      it "names the channel and handle in the subject" do
        expect(mail.subject).to eq("New LevelCode signup via linkedin / anastasia: #{user.email}")
      end

      it "shows the referral in the body" do
        body = mail.body.encoded
        expect(body).to match("linkedin")
        expect(body).to match("anastasia")
        expect(body).not_to match(/Organic/)
      end
    end

    # signup_attribution is client-controlled, and `source`/handle are interpolated
    # into the Subject.
    #
    # On the security question: this is NOT header injection. Mail
    # quoted-printable-encodes a CRLF inside a header value (it comes out as
    # `=0D=0A` on the Subject line), so a crafted value cannot open a new header
    # field, and Mail does not raise either. Verified against the encoded header
    # block — the field list stays Date/From/To/Message-ID/Subject/MIME-*.
    #
    # What it DOES cause is an unreadable subject full of `=0D=0A`, which is the
    # real (cosmetic) reason to scrub. These examples assert that, because it is
    # the behaviour that actually changes with the fix.
    context "a channel carrying control characters" do
      let(:user) do
        create(:user, signup_attribution: {
          "source" => "linkedin\r\nBcc: attacker@example.com",
          "params" => { "linkedin" => "anastasia\nX-Injected: yes" }
        })
      end

      it "builds a subject with no control characters" do
        subject_line = UserMailer.created(user).subject
        expect(subject_line).not_to match(/[[:cntrl:]]/)
        expect(subject_line).to include("linkedin")
      end

      # The handle is the other interpolated value, so it needs its own case: with a
      # mangled `source` the params lookup cannot match a key, so no handle is found
      # and the channel scrub alone would be exercised.
      it "scrubs control characters coming from the HANDLE" do
        referred = create(:user, signup_attribution: {
          "source" => "linkedin",
          "params" => { "linkedin" => "anastasia\r\nX-Injected: yes" }
        })

        subject_line = UserMailer.created(referred).subject
        expect(subject_line).not_to match(/[[:cntrl:]]/)
        expect(subject_line).to include("linkedin")
        expect(subject_line).to include("anastasia")
      end

      it "does not leak quoted-printable escapes into the encoded Subject" do
        mail = UserMailer.created(user)
        subject_line = mail.encoded.split(/\r?\n\r?\n/, 2).first.lines.map(&:chomp)
                           .find { |l| l.start_with?("Subject:") }

        expect(subject_line).not_to include("=0D")
        expect(subject_line).not_to include("=0A")
      end

      it "still addresses only the configured notification recipient" do
        expect(UserMailer.created(user).to).to eq([ "test@example.com" ])
      end
    end

    context "a channel with no handle" do
      let(:user) { create(:user, signup_attribution: { "source" => "linkedin", "params" => {} }) }

      it "falls back to the channel alone" do
        expect(UserMailer.created(user).subject).to eq("New LevelCode signup via linkedin: #{user.email}")
      end
    end

    context "sign-up method" do
      it "reports GitHub" do
        user = create(:user, provider: Levelcode::ProviderOAuth::GITHUB_PROVIDER, uid: "12345")
        expect(UserMailer.created(user).body.encoded).to match("GitHub")
      end

      # Google's stored provider is "google_oauth2", not "google" — a literal
      # comparison falls through and reports Google signups as Email.
      it "reports Google for the real stored provider value" do
        expect(User::GOOGLE_PROVIDER).to eq("google_oauth2")
        user = create(:user, provider: User::GOOGLE_PROVIDER, uid: "67890")
        body = UserMailer.created(user).body.encoded
        expect(body).to match("Google")
        expect(body).not_to match(/Signed up with[^<]*<\/td>\s*<td[^>]*>\s*Email/)
      end

      it "reports Email otherwise" do
        expect(UserMailer.created(create(:user)).body.encoded).to match("Email")
      end
    end
  end
end
