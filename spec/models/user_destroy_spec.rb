# frozen_string_literal: true

require "rails_helper"

# Deleting a user used to fail on a PG::ForeignKeyViolation: several tables have a
# foreign key to users (or to links, which cascade from users) with no matching
# association, so nothing cleaned them up. It failed ONE TABLE AT A TIME — the
# first violation aborts the transaction — so fixing a single table just moved the
# error along.
#
# This builds a user carrying a row in every table on that path and destroys them.
RSpec.describe "User#destroy with dependent records", type: :model do
  before { StripeMock.start }
  after { StripeMock.stop }

  # Deleting a user calls Stripe (`after_commit :delete_stripe_customer, on: :destroy`
  # -> Stripe::Customer.retrieve(stripe_id).delete), a real external call. Stubbed so
  # these examples exercise the DB cascade and nothing reaches Stripe.
  let(:stripe_customer) { instance_double(Stripe::Customer, delete: true) }

  before do
    allow(Stripe::Customer).to receive(:create)
      .and_return(Stripe::Customer.construct_from(id: "cus_test"))
    allow(Stripe::Customer).to receive(:retrieve).and_return(stripe_customer)
  end

  let!(:user) { create(:user, email: "doomed@example.com") }
  let!(:link) { create(:link, user: user, original_url: "https://levelcode.ai/ai?linkedin=x") }

  before do
    # --- children of users ---
    AuthEvent.create!(user: user, email: user.email, kind: "login", outcome: "success")
    UsageEvent.create!(user: user, model: "m", provider: "openrouter",
                       input_tokens: 1, output_tokens: 1, cost_micros: 1)
    UsageFeedback.create!(user: user, model: "m", rating: "up")
    CreditWallet.create!(user: user, product: "levelcode", plan_key: "free",
                         input_cap: 1, output_cap: 1, period_start: Time.current,
                         period_end: 1.month.from_now, overage_policy: "throttle")

    # --- children of links (reached by cascade) ---
    Click.create!(link: link, is_bot: false)
    LinkDestinationHistory.create!(link: link, destination_url: "https://levelcode.ai/ai",
                                   active_from: Time.current)
    LinkRoutingRule.create!(link: link, rule_type: "geo", conditions: {},
                            destination_url: "https://levelcode.ai/ai", priority: 1)
    LinkGovernanceLog.create!(link: link, user: user, action: "paused")
    ProfileLink.create!(profile: user.profile, link: link, position: 0)
  end

  it "destroys the user without a foreign-key violation" do
    expect { user.destroy! }.not_to raise_error
    expect(User.where(id: user.id)).to be_empty
  end

  it "takes the link and its children with it" do
    link_id = link.id
    user.destroy!

    expect(Link.where(id: link_id)).to be_empty
    expect(Click.where(link_id: link_id)).to be_empty
    expect(LinkDestinationHistory.where(link_id: link_id)).to be_empty
    expect(LinkRoutingRule.where(link_id: link_id)).to be_empty
    expect(ProfileLink.where(link_id: link_id)).to be_empty
  end

  # The audit trail is the reason auth_events.user_id is nullable: the record that
  # SOMEONE authenticated should survive erasing who they were.
  it "keeps auth events but detaches them from the deleted user" do
    user.destroy!

    events = AuthEvent.where(email: "doomed@example.com")
    expect(events).not_to be_empty
    expect(events.pluck(:user_id)).to all(be_nil)
  end

  it "removes usage feedback, which cannot be orphaned (user_id is NOT NULL)" do
    user_id = user.id
    user.destroy!
    expect(UsageFeedback.where(user_id: user_id)).to be_empty
  end

  # The Stripe cleanup runs after the DB transaction commits and is best-effort.
  # Before that, it ran inside the transaction and could roll the whole deletion
  # back — which is easy to hit now that the cascade actually reaches it.
  describe "Stripe customer cleanup" do
    # The factory no-ops create_stripe_customer, so a built user has NO stripe_id.
    # That default is itself the bug this guards: the old code called
    # Stripe::Customer.retrieve(nil), which raised INSIDE the destroy transaction
    # and rolled the deletion back.
    it "deletes a user that has no stripe_id, without calling Stripe" do
      expect(user.stripe_id).to be_blank

      expect { user.destroy! }.not_to raise_error
      expect(User.where(id: user.id)).to be_empty
      expect(Stripe::Customer).not_to have_received(:retrieve)
    end

    it "deletes the customer when there is one" do
      user.update_columns(stripe_id: "cus_test")

      user.destroy!
      expect(stripe_customer).to have_received(:delete)
    end

    it "keeps the user deleted when Stripe fails, and logs it" do
      user.update_columns(stripe_id: "cus_test")
      allow(Stripe::Customer).to receive(:retrieve).and_raise(Stripe::APIError.new("stripe is down"))
      allow(Rails.logger).to receive(:warn)
      user_id = user.id

      expect { user.destroy! }.not_to raise_error
      expect(User.where(id: user_id)).to be_empty
      expect(Rails.logger).to have_received(:warn).with(/Stripe customer .* was not deleted/)
    end
  end
end
