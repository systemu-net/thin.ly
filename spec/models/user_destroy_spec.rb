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
  let(:stripe_helper) { StripeMock.create_test_helper }
  before { StripeMock.start }
  after { StripeMock.stop }

  # User has `after_destroy :delete_stripe_customer`, which does
  # Stripe::Customer.retrieve(stripe_id).delete — a real external call. Stubbed so
  # these examples test the DB cascade and nothing reaches Stripe.
  before do
    allow(Stripe::Customer).to receive(:create)
      .and_return(Stripe::Customer.construct_from(id: "cus_test"))
    allow(Stripe::Customer).to receive(:retrieve)
      .and_return(instance_double(Stripe::Customer, delete: true))
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
end
