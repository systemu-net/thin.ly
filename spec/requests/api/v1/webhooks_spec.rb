require "rails_helper"

# rubocop:disable Metrics/BlockLength
RSpec.describe "Api::V1::Webhooks", type: :request do
  WEBHOOK_URL = "/api/v1/webhooks"

  # ─── Stripe IDs ───────────────────────────────────────────────────────────────
  let(:stripe_customer_id)     { "cus_test123" }
  let(:stripe_subscription_id) { "sub_test123" }
  let(:stripe_product_id)      { "prod_test123" }

  # ─── Database records ────────────────────────────────────────────────────────
  #
  # IMPORTANT: The User model has two auto-create callbacks:
  #   1. `before_commit :create_default_subscription` – creates one Subscription
  #      with customer_id = stripe_id.
  #   2. Subscription has `after_commit :create_default_plan` – creates a Plan.
  #
  # Also, UserNotifier#send_created_email fires after_create and enqueues
  # UserNotificationWorker, which runs inline (Sidekiq::Testing.inline!) and
  # delivers a welcome email.
  #
  # Strategy:
  #   • `let(:subscription)` taps the auto-created subscription and updates its
  #     columns to match test expectations, rather than creating a second one.
  #     This prevents `Subscription.find_by(customer_id:)` from returning the
  #     wrong record.
  #   • `before` blocks that care about email counts call
  #     `ActionMailer::Base.deliveries.clear` AFTER user/subscription setup so
  #     the welcome email doesn't pollute assertions.
  #   • "No subscription" contexts call `user.subscriptions.destroy_all` to
  #     remove the auto-created subscription.

  let(:user) { create(:user, stripe_id: stripe_customer_id) }

  let(:subscription) do
    user.subscriptions.first!.tap do |sub|
      sub.update_columns(
        subscription_id:      stripe_subscription_id,
        status:               "active",
        interval:             "month",
        current_period_start: 1.month.ago,
        current_period_end:   1.month.from_now
      )
    end
  end

  # The Plan is auto-created by the Subscription after_commit callback.
  let(:plan) { subscription.plan }

  before { ActionMailer::Base.deliveries.clear }

  # ─── Test Helpers ────────────────────────────────────────────────────────────

  def post_stripe_webhook(event, payload: "{}")
    allow(Stripe::Webhook).to receive(:construct_event).and_return(event)
    post WEBHOOK_URL,
         params:  payload,
         headers: { "Content-Type"     => "application/json",
                    "Stripe-Signature" => "t=#{Time.now.to_i},v1=fake_sig" }
  end

  def build_event(type, object, id: "evt_#{SecureRandom.hex(8)}")
    data = double("event_data", object: object)
    double("Stripe::Event", id: id, type: type, data: data)
  end

  # ── Stripe object builders ────────────────────────────────────────────────

  def build_checkout_session(customer: stripe_customer_id, id: "cs_test123",
                              mode: "subscription", subscription: stripe_subscription_id)
    double("Stripe::CheckoutSession", id: id, customer: customer, mode: mode, subscription: subscription)
  end

  # Pass `subscription_id: nil` to simulate a one-off (non-subscription) invoice.
  def build_invoice(customer: stripe_customer_id, billing_reason: "subscription_cycle",
                    id: "in_test123", hosted_invoice_url: "https://invoice.stripe.com/x",
                    subscription_id: stripe_subscription_id,
                    amount_paid: 1999, currency: "usd",
                    charge: "ch_test123",
                    payment_intent: "pi_test123",
                    invoice_pdf: "https://pay.stripe.com/invoice/test/pdf")
    sub_details = double("subscription_details", subscription: subscription_id)
    parent      = double("parent", subscription_details: sub_details)
    double("Stripe::Invoice",
           id:                 id,
           customer:           customer,
           billing_reason:     billing_reason,
           hosted_invoice_url: hosted_invoice_url,
           parent:             parent,
           subscription:       subscription_id,
           amount_paid:        amount_paid,
           currency:           currency,
           charge:             charge,
           payment_intent:     payment_intent,
           invoice_pdf:        invoice_pdf)
  end

  def build_stripe_subscription(id: stripe_subscription_id, customer: stripe_customer_id,
                                status: "active", interval: "month",
                                product_id: stripe_product_id,
                                period_start: 30.days.ago.to_i,
                                period_end: 30.days.from_now.to_i,
                                trial_end: 7.days.from_now.to_i,
                                cancel_at_period_end: false,
                                price_id: "price_test123",
                                plan_nickname: "Pro",
                                price_nickname: "Pro Monthly",
                                lookup_key: nil)
    plan_double = double("stripe_plan", product: product_id, interval: interval, nickname: plan_nickname)
    # `lookup_key` is what both Levelcode::WebhookSync AND the shortener handlers read to
    # tell the two products apart. Shortener prices don't set one (nil); a LevelCode Cloud
    # price carries a Levelcode::PLANS key (e.g. "orbits_pro"). Pass `lookup_key:` to
    # simulate a LevelCode subscription reaching this shared webhook.
    price_double = double("stripe_price", id: price_id, nickname: price_nickname, product: product_id, lookup_key: lookup_key)
    item_double = double("stripe_item",
                         plan:                 plan_double,
                         price:                price_double,
                         current_period_start: period_start,
                         current_period_end:   period_end)
    double("Stripe::Subscription",
           id:                   id,
           customer:             customer,
           status:               status,
           plan:                 plan_double,
           items:                double("items", data: [ item_double ]),
           trial_end:            trial_end,
           cancel_at_period_end: cancel_at_period_end,
           latest_invoice:       "in_checkout_test123")
  end

  # Stubs Stripe::Subscription.retrieve (used by invoice.paid),
  # Stripe::Product.retrieve (used by sync_subscription), and
  # Stripe::Charge.retrieve (used by extract_invoice_data).
  def stub_stripe_api(stripe_sub: nil,
                      metadata: { "name" => "Pro", "links" => "200",
                                  "qr_codes" => "100", "brand_pages" => "10" },
                      card_last4: "4242")
    stripe_sub ||= build_stripe_subscription
    meta_double    = double("metadata", as_json: metadata)
    product_double = double("Stripe::Product", metadata: meta_double, name: "Pro")
    allow(Stripe::Subscription).to receive(:retrieve).and_return(stripe_sub)
    allow(Stripe::Product).to receive(:retrieve).and_return(product_double)

    # Stub charge retrieval for card details in receipt emails
    card_double   = double("card", last4: card_last4)
    pm_details    = double("payment_method_details", card: card_double)
    charge_double = double("Stripe::Charge", payment_method_details: pm_details)
    allow(Stripe::Charge).to receive(:retrieve).and_return(charge_double)

    # Stub payment intent retrieval (fallback for card details)
    pi_double = double("Stripe::PaymentIntent", latest_charge: "ch_test123")
    allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(pi_double)

    # Stub invoice retrieval for checkout confirmation emails
    sub_details_double = double("subscription_details", subscription: stripe_sub.id)
    parent_double      = double("parent", subscription_details: sub_details_double)
    invoice_double = double("Stripe::Invoice",
                            id:                 "in_checkout_test123",
                            customer:           stripe_sub.customer,
                            billing_reason:     "subscription_create",
                            hosted_invoice_url: "https://invoice.stripe.com/x",
                            parent:             parent_double,
                            subscription:       stripe_sub.id,
                            amount_paid:        1999,
                            currency:           "usd",
                            charge:             "ch_test123",
                            payment_intent:     "pi_test123",
                            invoice_pdf:        "https://pay.stripe.com/invoice/test/pdf")
    allow(Stripe::Invoice).to receive(:retrieve).and_return(invoice_double)

    stripe_sub
  end

  # ─── Tests ───────────────────────────────────────────────────────────────────

  describe "POST /api/v1/webhooks" do
    # ── Signature / payload validation ──────────────────────────────────────

    context "when the JSON payload is malformed" do
      it "returns 400 with an error body" do
        allow(Stripe::Webhook).to receive(:construct_event)
          .and_raise(JSON::ParserError, "unexpected token")

        post WEBHOOK_URL,
             params: "not{json",
             headers: { "Content-Type" => "application/json", "Stripe-Signature" => "t=1,v1=x" }

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body).to include("error" => "Invalid payload")
      end
    end

    context "when the Stripe signature does not match" do
      it "returns 400 with an error body" do
        allow(Stripe::Webhook).to receive(:construct_event)
          .and_raise(Stripe::SignatureVerificationError.new("bad sig", "header"))

        post WEBHOOK_URL,
             params: "{}",
             headers: { "Content-Type" => "application/json", "Stripe-Signature" => "t=1,v1=bad" }

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body).to include("error" => "Invalid signature")
      end
    end

    # ── Idempotency ──────────────────────────────────────────────────────────

    context "when the event has already been processed (duplicate delivery)" do
      let(:event_id) { "evt_duplicate_001" }
      let(:obj)      { build_checkout_session }
      let(:event)    { build_event("checkout.session.completed", obj, id: event_id) }

      before do
        ProcessedStripeEvent.create!(
          stripe_event_id: event_id,
          event_type:      "checkout.session.completed",
          processed_at:    Time.current
        )
      end

      it "returns 200 OK" do
        post_stripe_webhook(event)
        expect(response).to have_http_status(:ok)
      end

      it "does not create another ProcessedStripeEvent record" do
        expect { post_stripe_webhook(event) }
          .not_to change(ProcessedStripeEvent, :count)
      end

      it "does not send any emails" do
        post_stripe_webhook(event)
        expect(ActionMailer::Base.deliveries).to be_empty
      end
    end

    # ── ProcessedStripeEvent tracking ────────────────────────────────────────

    context "on a first-time processed event" do
      let(:obj)   { build_checkout_session }
      let(:event) { build_event("checkout.session.completed", obj) }

      it "creates exactly one ProcessedStripeEvent record" do
        expect { post_stripe_webhook(event) }
          .to change(ProcessedStripeEvent, :count).by(1)
      end

      it "stores the event id and type" do
        post_stripe_webhook(event)
        record = ProcessedStripeEvent.last
        expect(record.stripe_event_id).to eq(event.id)
        expect(record.event_type).to eq("checkout.session.completed")
      end
    end

    # ── Stripe API error during handle_event: transient → retry, permanent → ack ──

    context "when a TRANSIENT Stripe error occurs (network / rate-limit / 5xx)" do
      let(:event) { build_event("invoice.paid", build_invoice) }

      before do
        user
        subscription
        allow(Stripe::Subscription).to receive(:retrieve)
          .and_raise(Stripe::APIConnectionError.new("network error"))
      end

      it "returns a non-2xx so Stripe retries the webhook" do
        post_stripe_webhook(event)
        expect(response).to have_http_status(:internal_server_error)
      end

      it "releases the idempotency claim so the retry re-runs the sync" do
        expect { post_stripe_webhook(event) }
          .not_to change(ProcessedStripeEvent, :count) # claimed then released → net zero
        expect(ProcessedStripeEvent.exists?(stripe_event_id: event.id)).to be(false)
      end
    end

    context "when a PERMANENT Stripe error occurs (bad request / auth)" do
      let(:event) { build_event("invoice.paid", build_invoice) }

      before do
        user
        subscription
        allow(Stripe::Subscription).to receive(:retrieve)
          .and_raise(Stripe::InvalidRequestError.new("no such subscription", "subscription"))
      end

      it "returns 200 (retrying can't help — don't churn Stripe's retry queue)" do
        post_stripe_webhook(event)
        expect(response).to have_http_status(:ok)
      end

      it "records the event as processed (no retry)" do
        expect { post_stripe_webhook(event) }
          .to change(ProcessedStripeEvent, :count).by(1)
      end
    end

    # ── checkout.session.completed ───────────────────────────────────────────

    describe "checkout.session.completed" do
      let(:obj)   { build_checkout_session(customer: user.stripe_id) }
      let(:event) { build_event("checkout.session.completed", obj) }

      before do
        subscription # ensure the DB subscription exists
        stub_stripe_api
        ActionMailer::Base.deliveries.clear
      end

      it "returns 200" do
        post_stripe_webhook(event)
        expect(response).to have_http_status(:ok)
      end

      it "syncs the subscription from the checkout session" do
        post_stripe_webhook(event)
        subscription.reload
        expect(subscription.status).to eq("active")
        expect(subscription.subscription_id).to eq(stripe_subscription_id)
      end

      it "sends a payment_completed welcome email" do
        post_stripe_webhook(event)
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        mail = ActionMailer::Base.deliveries.first
        expect(mail.to).to      include(user.email)
        expect(mail.subject).to eq("Welcome to thin.ly - Payment Confirmed")
      end

      it "attaches the invoice PDF to the welcome email" do
        # Stub Net::HTTP to return fake PDF content instead of hitting the real URL
        pdf_content = "%PDF-1.4 fake"
        http_response = Net::HTTPSuccess.allocate
        allow(http_response).to receive(:body).and_return(pdf_content)

        http_double = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http_double)
        allow(http_double).to receive(:use_ssl=)
        allow(http_double).to receive(:open_timeout=)
        allow(http_double).to receive(:read_timeout=)
        allow(http_double).to receive(:request).and_return(http_response)

        post_stripe_webhook(event)
        mail = ActionMailer::Base.deliveries.first
        expect(mail.attachments.count).to eq(1)
        expect(mail.attachments.first.filename).to eq("receipt.pdf")
      end

      it "records the event as processed" do
        expect { post_stripe_webhook(event) }
          .to change(ProcessedStripeEvent, :count).by(1)
      end

      context "when mode is not subscription" do
        let(:obj) { build_checkout_session(customer: user.stripe_id, mode: "payment", subscription: nil) }

        it "does not call Stripe Subscription API" do
          expect(Stripe::Subscription).not_to receive(:retrieve)
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end
      end
    end

    # ── checkout.session.async_payment_succeeded ─────────────────────────────

    describe "checkout.session.async_payment_succeeded" do
      let(:obj)   { build_checkout_session(customer: user.stripe_id) }
      let(:event) { build_event("checkout.session.async_payment_succeeded", obj) }

      before do
        subscription
        stub_stripe_api
        ActionMailer::Base.deliveries.clear
      end

      it "returns 200" do
        post_stripe_webhook(event)
        expect(response).to have_http_status(:ok)
      end

      it "syncs the subscription from the checkout session" do
        post_stripe_webhook(event)
        subscription.reload
        expect(subscription.status).to eq("active")
        expect(subscription.subscription_id).to eq(stripe_subscription_id)
      end

      it "sends a payment_completed welcome email" do
        post_stripe_webhook(event)
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        mail = ActionMailer::Base.deliveries.first
        expect(mail.to).to      include(user.email)
        expect(mail.subject).to eq("Welcome to thin.ly - Payment Confirmed")
      end
    end

    # ── checkout.session.async_payment_failed ────────────────────────────────

    describe "checkout.session.async_payment_failed" do
      # The failure handler now resolves the subscription's product before emailing; stub the
      # retrieve so skip_levelcode_id? sees a shortener price (lookup_key nil) and proceeds normally.
      before { allow(Stripe::Subscription).to receive(:retrieve).and_return(build_stripe_subscription) }

      context "when the user exists" do
        let(:obj)   { build_checkout_session(customer: user.stripe_id) }
        let(:event) { build_event("checkout.session.async_payment_failed", obj) }

        before do
          user
          ActionMailer::Base.deliveries.clear # discard user welcome email
        end

        it "returns 200" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "sends exactly one payment_failed email to the user" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries.count).to eq(1)
          mail = ActionMailer::Base.deliveries.first
          expect(mail.to).to      include(user.email)
          expect(mail.subject).to eq("thin.ly - Payment Attempt Failed")
        end
      end

      context "when no user matches the Stripe customer" do
        let(:obj)   { build_checkout_session(customer: "cus_nobody") }
        let(:event) { build_event("checkout.session.async_payment_failed", obj) }

        it "returns 200 without raising" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "does not send any email" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end
    end

    # ── invoice.paid ─────────────────────────────────────────────────────────

    describe "invoice.paid" do
      context "for initial subscription creation (billing_reason: subscription_create)" do
        let(:invoice)    { build_invoice(billing_reason: "subscription_create") }
        let(:event)      { build_event("invoice.paid", invoice) }
        let(:stripe_sub) { build_stripe_subscription }

        before do
          user
          subscription  # tap-updates the auto-created subscription
          plan          # eager-evaluate so we can reload it after the webhook
          stub_stripe_api(stripe_sub: stripe_sub)
          ActionMailer::Base.deliveries.clear # discard welcome email
        end

        it "returns 200" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "updates subscription status, interval, and subscription_id" do
          post_stripe_webhook(event)
          sub = subscription.reload
          expect(sub.status).to          eq("active")
          expect(sub.interval).to        eq("month")
          expect(sub.subscription_id).to eq(stripe_sub.id)
        end

        it "syncs period dates from the subscription item" do
          post_stripe_webhook(event)
          sub = subscription.reload
          expect(sub.current_period_start).to be_present
          expect(sub.current_period_end).to   be_present
        end

        it "updates plan limits and name from Stripe product metadata" do
          post_stripe_webhook(event)
          plan.reload
          expect(plan.name).to        eq("Pro")
          expect(plan.links).to       eq(200)
          expect(plan.qr_codes).to    eq(100)
          expect(plan.brand_pages).to eq(10)
        end

        it "does not send a duplicate email (checkout fulfillment handles it)" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end

      context "for a recurring renewal (billing_reason: subscription_cycle)" do
        let(:invoice)    { build_invoice(billing_reason: "subscription_cycle") }
        let(:event)      { build_event("invoice.paid", invoice) }
        let(:stripe_sub) { build_stripe_subscription }

        before do
          user
          subscription
          plan
          stub_stripe_api(stripe_sub: stripe_sub)
          ActionMailer::Base.deliveries.clear
        end

        it "sends a payment_successful email (renewal, not first-purchase)" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries.count).to eq(1)
          mail = ActionMailer::Base.deliveries.first
          expect(mail.to).to      include(user.email)
          expect(mail.subject).to eq("thin.ly - Payment Receipt - Thank You")
        end

        it "syncs subscription and plan data" do
          post_stripe_webhook(event)
          expect(subscription.reload.status).to eq("active")
          expect(plan.reload.name).to eq("Pro")
        end
      end

      context "when the invoice is not subscription-related (no subscription_id)" do
        let(:invoice) { build_invoice(subscription_id: nil) }
        let(:event)   { build_event("invoice.paid", invoice) }

        it "returns 200 and skips Stripe API calls" do
          expect(Stripe::Subscription).not_to receive(:retrieve)
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "does not send any email" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end

      context "when no user matches the Stripe customer" do
        let(:invoice) { build_invoice(customer: "cus_unknown_xyz") }
        let(:event)   { build_event("invoice.paid", invoice) }

        it "returns 200 without raising" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "does not send any email" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end

      context "when the user exists but has no Subscription record" do
        let(:invoice)    { build_invoice }
        let(:event)      { build_event("invoice.paid", invoice) }
        let(:stripe_sub) { build_stripe_subscription }

        before do
          user
          user.subscriptions.destroy_all # remove the auto-created subscription
          allow(Stripe::Subscription).to receive(:retrieve).and_return(stripe_sub)
          ActionMailer::Base.deliveries.clear
        end

        it "returns 200 without raising" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "does not send any email" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end

      context "when Stripe product metadata is empty" do
        let(:invoice)    { build_invoice(billing_reason: "subscription_cycle") }
        let(:event)      { build_event("invoice.paid", invoice) }
        let(:stripe_sub) { build_stripe_subscription }

        before do
          user
          subscription
          plan
          stub_stripe_api(stripe_sub: stripe_sub, metadata: {})
          ActionMailer::Base.deliveries.clear
        end

        it "returns 200 (graceful handling)" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "still syncs subscription status and periods even without metadata" do
          post_stripe_webhook(event)
          sub = subscription.reload
          expect(sub.status).to eq("active")
          expect(sub.current_period_start).to be_present
          expect(sub.current_period_end).to be_present
        end

        it "does not update plan attributes when metadata is absent" do
          original_name = plan.name
          post_stripe_webhook(event)
          expect(plan.reload.name).to eq(original_name)
        end
      end

      context "when Stripe::Product.retrieve raises a Stripe API error" do
        let(:invoice)    { build_invoice(billing_reason: "subscription_cycle") }
        let(:event)      { build_event("invoice.paid", invoice) }
        let(:stripe_sub) { build_stripe_subscription }

        before do
          user
          subscription
          plan
          stub_stripe_api(stripe_sub: stripe_sub)
          allow(Stripe::Product).to receive(:retrieve)
            .and_raise(Stripe::APIConnectionError.new("Connection refused"))
          ActionMailer::Base.deliveries.clear
        end

        it "returns 200 (graceful handling)" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "still syncs subscription status and periods despite the API error" do
          post_stripe_webhook(event)
          sub = subscription.reload
          expect(sub.status).to eq("active")
          expect(sub.current_period_start).to be_present
          expect(sub.current_period_end).to be_present
        end

        it "does not update plan attributes when the product API call fails" do
          original_name = plan.name
          post_stripe_webhook(event)
          expect(plan.reload.name).to eq(original_name)
        end
      end
    end

    # ── invoice.payment_succeeded ────────────────────────────────────────────
    # Handled identically to invoice.paid (covers the case where only
    # invoice.payment_succeeded is enabled on the Stripe webhook endpoint).

    describe "invoice.payment_succeeded" do
      let(:invoice)    { build_invoice(billing_reason: "subscription_cycle") }
      let(:event)      { build_event("invoice.payment_succeeded", invoice) }
      let(:stripe_sub) { build_stripe_subscription }

      before do
        user
        subscription
        plan
        stub_stripe_api(stripe_sub: stripe_sub)
        ActionMailer::Base.deliveries.clear
      end

      it "returns 200" do
        post_stripe_webhook(event)
        expect(response).to have_http_status(:ok)
      end

      it "syncs the subscription (same as invoice.paid)" do
        post_stripe_webhook(event)
        sub = subscription.reload
        expect(sub.status).to          eq("active")
        expect(sub.subscription_id).to eq(stripe_sub.id)
      end

      it "updates plan limits from Stripe product metadata" do
        post_stripe_webhook(event)
        plan.reload
        expect(plan.name).to        eq("Pro")
        expect(plan.links).to       eq(200)
        expect(plan.qr_codes).to    eq(100)
        expect(plan.brand_pages).to eq(10)
      end

      it "sends a payment_successful email" do
        post_stripe_webhook(event)
        expect(ActionMailer::Base.deliveries.count).to eq(1)
        mail = ActionMailer::Base.deliveries.first
        expect(mail.to).to include(user.email)
      end
    end

    # ── invoice.payment_failed ───────────────────────────────────────────────

    describe "invoice.payment_failed" do
      # The handler resolves the invoice's subscription product before emailing; stub the retrieve
      # so skip_levelcode_id? sees a shortener price (lookup_key nil) and proceeds normally.
      before { allow(Stripe::Subscription).to receive(:retrieve).and_return(build_stripe_subscription) }

      context "when the user exists" do
        let(:invoice) { build_invoice(customer: user.stripe_id) }
        let(:event)   { build_event("invoice.payment_failed", invoice) }

        before do
          user
          ActionMailer::Base.deliveries.clear
        end

        it "returns 200" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "sends a payment_failed email to the user" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries.count).to eq(1)
          mail = ActionMailer::Base.deliveries.first
          expect(mail.to).to      include(user.email)
          expect(mail.subject).to eq("thin.ly - Payment Attempt Failed")
        end
      end

      context "when no user matches the Stripe customer" do
        let(:invoice) { build_invoice(customer: "cus_nobody") }
        let(:event)   { build_event("invoice.payment_failed", invoice) }

        it "returns 200 without raising" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "does not send any email" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end
    end

    # ── invoice.payment_action_required ─────────────────────────────────────

    describe "invoice.payment_action_required" do
      # The handler resolves the invoice's subscription product before emailing; stub the retrieve
      # so skip_levelcode_id? sees a shortener price (lookup_key nil) and proceeds normally.
      before { allow(Stripe::Subscription).to receive(:retrieve).and_return(build_stripe_subscription) }

      context "when the user exists" do
        let(:invoice) { build_invoice(customer: user.stripe_id) }
        let(:event)   { build_event("invoice.payment_action_required", invoice) }

        before do
          user
          ActionMailer::Base.deliveries.clear
        end

        it "returns 200" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "sends a payment_action_required email to the user" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries.count).to eq(1)
          mail = ActionMailer::Base.deliveries.first
          expect(mail.to).to      include(user.email)
          expect(mail.subject).to eq("thin.ly - Action Required to Complete Payment")
        end

        it "includes the hosted invoice URL in the email body" do
          post_stripe_webhook(event)
          mail = ActionMailer::Base.deliveries.first
          expect(mail.body.encoded).to include("https://invoice.stripe.com/x")
        end

        it "does not raise" do
          expect { post_stripe_webhook(event) }.not_to raise_error
        end
      end

      context "when no user matches the Stripe customer" do
        let(:invoice) { build_invoice(customer: "cus_nobody") }
        let(:event)   { build_event("invoice.payment_action_required", invoice) }

        it "returns 200" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "does not send any email" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end
    end

    # ── customer.subscription.updated ───────────────────────────────────────

    describe "customer.subscription.updated" do
      context "when both the user and subscription record exist" do
        let(:stripe_sub) { build_stripe_subscription(status: "past_due") }
        let(:event)      { build_event("customer.subscription.updated", stripe_sub) }

        before do
          user
          subscription
          plan
          stub_stripe_api(stripe_sub: stripe_sub)
          ActionMailer::Base.deliveries.clear
        end

        it "returns 200" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "updates the subscription status" do
          post_stripe_webhook(event)
          expect(subscription.reload.status).to eq("past_due")
        end

        it "updates the subscription_id" do
          post_stripe_webhook(event)
          expect(subscription.reload.subscription_id).to eq(stripe_sub.id)
        end

        it "updates the interval" do
          post_stripe_webhook(event)
          expect(subscription.reload.interval).to eq("month")
        end

        it "syncs plan limits and name from Stripe product metadata" do
          post_stripe_webhook(event)
          plan.reload
          expect(plan.name).to        eq("Pro")
          expect(plan.links).to       eq(200)
          expect(plan.qr_codes).to    eq(100)
          expect(plan.brand_pages).to eq(10)
        end

        it "does not send any email" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end

      context "when no user matches the Stripe customer" do
        let(:stripe_sub) { build_stripe_subscription(customer: "cus_nobody") }
        let(:event)      { build_event("customer.subscription.updated", stripe_sub) }

        it "returns 200 without raising" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end
      end

      context "when the user has no Subscription record" do
        let(:stripe_sub) { build_stripe_subscription(customer: user.stripe_id) }
        let(:event)      { build_event("customer.subscription.updated", stripe_sub) }

        before do
          user
          user.subscriptions.destroy_all
        end

        it "returns 200 without raising" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end
      end

      context "when cancel_at_period_end changes from false to true (cancellation scheduled)" do
        let(:stripe_sub) { build_stripe_subscription(status: "active", cancel_at_period_end: true) }
        let(:event)      { build_event("customer.subscription.updated", stripe_sub) }

        before do
          user
          subscription
          subscription.update_columns(cancel_at_period_end: false)
          plan
          stub_stripe_api(stripe_sub: stripe_sub)
          ActionMailer::Base.deliveries.clear
        end

        it "returns 200" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "sets cancel_at_period_end to true" do
          post_stripe_webhook(event)
          expect(subscription.reload.cancel_at_period_end).to eq(true)
        end

        it "keeps the subscription status as active" do
          post_stripe_webhook(event)
          expect(subscription.reload.status).to eq("active")
        end

        it "does NOT reset the plan to free defaults" do
          post_stripe_webhook(event)
          plan.reload
          expect(plan.name).to eq("Pro")
          expect(plan.links).to eq(200)
        end

        it "sends a cancellation_scheduled email" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries.count).to eq(1)
          mail = ActionMailer::Base.deliveries.first
          expect(mail.to).to      include(user.email)
          expect(mail.subject).to eq("thin.ly - Subscription Cancellation Scheduled")
        end
      end

      context "when cancel_at_period_end changes from true to false (reactivation)" do
        let(:stripe_sub) { build_stripe_subscription(status: "active", cancel_at_period_end: false) }
        let(:event)      { build_event("customer.subscription.updated", stripe_sub) }

        before do
          user
          subscription
          subscription.update_columns(cancel_at_period_end: true)
          plan
          stub_stripe_api(stripe_sub: stripe_sub)
          ActionMailer::Base.deliveries.clear
        end

        it "returns 200" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "sets cancel_at_period_end back to false" do
          post_stripe_webhook(event)
          expect(subscription.reload.cancel_at_period_end).to eq(false)
        end

        it "keeps the subscription active" do
          post_stripe_webhook(event)
          expect(subscription.reload.status).to eq("active")
        end

        it "sends a subscription_reactivated email" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries.count).to eq(1)
          mail = ActionMailer::Base.deliveries.first
          expect(mail.to).to      include(user.email)
          expect(mail.subject).to eq("thin.ly - Subscription Reactivated")
        end
      end
    end

    # ── customer.subscription.deleted ───────────────────────────────────────

    describe "customer.subscription.deleted" do
      context "when both the user and subscription record exist" do
        let(:stripe_sub) { build_stripe_subscription }
        let(:event)      { build_event("customer.subscription.deleted", stripe_sub) }

        before do
          user
          subscription  # subscription_id: "sub_test123" — matches stripe_sub.id
          plan
          ActionMailer::Base.deliveries.clear
        end

        it "returns 200" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "sets subscription status to 'canceled'" do
          post_stripe_webhook(event)
          expect(subscription.reload.status).to eq("canceled")
        end

        it "clears subscription_id" do
          post_stripe_webhook(event)
          expect(subscription.reload.subscription_id).to be_nil
        end

        it "clears stripe_price_id" do
          subscription.update_columns(stripe_price_id: "price_test123")
          post_stripe_webhook(event)
          expect(subscription.reload.stripe_price_id).to be_nil
        end

        it "resets cancel_at_period_end to false" do
          subscription.update_columns(cancel_at_period_end: true)
          post_stripe_webhook(event)
          expect(subscription.reload.cancel_at_period_end).to eq(false)
        end

        it "resets the plan to free-tier defaults" do
          post_stripe_webhook(event)
          plan.reload
          expect(plan.name).to        eq(Plan::DEFAULT_PLAN[:name])
          expect(plan.links).to       eq(Plan::DEFAULT_PLAN[:links])
          expect(plan.qr_codes).to    eq(Plan::DEFAULT_PLAN[:qr_codes])
          expect(plan.brand_pages).to eq(Plan::DEFAULT_PLAN[:brand_pages])
        end

        it "sends a subscription_canceled email to the user" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries.count).to eq(1)
          mail = ActionMailer::Base.deliveries.first
          expect(mail.to).to      include(user.email)
          expect(mail.subject).to eq("thin.ly - Subscription Canceled")
        end

        it "does not call Stripe APIs" do
          expect(Stripe::Subscription).not_to receive(:retrieve)
          expect(Stripe::Product).not_to      receive(:retrieve)
          post_stripe_webhook(event)
        end
      end

      context "when no user matches the Stripe customer" do
        let(:stripe_sub) { build_stripe_subscription(customer: "cus_nobody") }
        let(:event)      { build_event("customer.subscription.deleted", stripe_sub) }

        it "returns 200 without raising" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "does not send any email" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end

      context "when the subscription record cannot be found (mismatched subscription_id)" do
        # stripe_sub.id is "sub_unknown" but the DB row has "sub_test123"
        let(:stripe_sub) { build_stripe_subscription(id: "sub_unknown") }
        let(:event)      { build_event("customer.subscription.deleted", stripe_sub) }

        before do
          user
          subscription  # has subscription_id: "sub_test123"
          ActionMailer::Base.deliveries.clear
        end

        it "returns 200 without raising" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "does not alter the existing subscription" do
          post_stripe_webhook(event)
          expect(subscription.reload.status).to eq("active")
        end

        it "does not send any email" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end
    end

    # ── customer.subscription.trial_will_end ────────────────────────────────

    describe "customer.subscription.trial_will_end" do
      context "when the user exists" do
        let(:stripe_sub) { build_stripe_subscription(trial_end: 3.days.from_now.to_i) }
        let(:event)      { build_event("customer.subscription.trial_will_end", stripe_sub) }

        before do
          user
          ActionMailer::Base.deliveries.clear
        end

        it "returns 200" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end

        it "does not send any email (email sending is a TODO in the controller)" do
          post_stripe_webhook(event)
          expect(ActionMailer::Base.deliveries).to be_empty
        end

        it "does not raise" do
          expect { post_stripe_webhook(event) }.not_to raise_error
        end
      end

      context "when no user matches the Stripe customer" do
        let(:stripe_sub) { build_stripe_subscription(customer: "cus_nobody") }
        let(:event)      { build_event("customer.subscription.trial_will_end", stripe_sub) }

        it "returns 200 without raising" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
        end
      end
    end

    # ── Product-key routing: LevelCode Cloud events must NOT touch the shortener ──
    #
    # One Stripe account hosts both products. Levelcode::WebhookSync owns LevelCode
    # subscriptions (price lookup_key ∈ Levelcode::PLANS) and provisions the CreditWallet.
    # The shortener handlers must skip them — otherwise a LevelCode purchase resolves to the
    # user's link-shortener Subscription row and its empty links/qr_codes metadata zeroes the
    # shortener Plan. Here WebhookSync is stubbed (its own behavior lives in webhook_sync_spec);
    # we assert only that the SHORTENER side leaves the Plan/Subscription untouched and sends
    # no shortener email.
    describe "LevelCode Cloud subscriptions (product-key routing)" do
      let(:levelcode_sub) { build_stripe_subscription(lookup_key: "orbits_pro") }

      before do
        user
        subscription # active shortener subscription
        plan
        # Give the shortener Plan distinctive values so we can prove they are NOT modified.
        plan.update_columns(name: "Shortener Pro", links: 200, qr_codes: 100, brand_pages: 10)
        allow(Levelcode::WebhookSync).to receive(:call) # isolate the shortener side
        ActionMailer::Base.deliveries.clear
      end

      context "checkout.session.completed" do
        let(:obj)   { build_checkout_session(customer: user.stripe_id) }
        let(:event) { build_event("checkout.session.completed", obj) }

        before { allow(Stripe::Subscription).to receive(:retrieve).and_return(levelcode_sub) }

        it "returns 200, leaves the shortener Plan intact, and sends no shortener email" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
          expect(plan.reload.name).to eq("Shortener Pro")
          expect(plan.links).to eq(200)
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end

      context "invoice.paid" do
        let(:invoice) { build_invoice(billing_reason: "subscription_cycle") }
        let(:event)   { build_event("invoice.paid", invoice) }

        before { allow(Stripe::Subscription).to receive(:retrieve).and_return(levelcode_sub) }

        it "returns 200, does not zero the shortener Plan, and sends no shortener email" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
          expect(plan.reload.links).to eq(200)
          expect(subscription.reload.status).to eq("active")
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end

      context "customer.subscription.updated" do
        let(:event) { build_event("customer.subscription.updated", levelcode_sub) }

        it "returns 200 and does not touch the shortener Subscription/Plan" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
          expect(plan.reload.links).to eq(200)
          expect(subscription.reload.status).to eq("active")
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end

      context "customer.subscription.deleted (even when the Stripe sub id matches the shortener row)" do
        # Worst case: the ids collide. The lookup_key guard must still protect the shortener —
        # a LevelCode cancellation must not reset the shortener Plan to Free or cancel its sub.
        let(:levelcode_sub) { build_stripe_subscription(id: stripe_subscription_id, lookup_key: "orbits_pro") }
        let(:event) { build_event("customer.subscription.deleted", levelcode_sub) }

        it "returns 200 and does NOT cancel the shortener sub or reset its Plan to Free" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
          expect(subscription.reload.status).to eq("active")
          expect(plan.reload.name).to eq("Shortener Pro")
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end

      context "invoice.payment_failed for a LevelCode subscription" do
        let(:invoice) { build_invoice(customer: user.stripe_id) }
        let(:event)   { build_event("invoice.payment_failed", invoice) }

        before { allow(Stripe::Subscription).to receive(:retrieve).and_return(levelcode_sub) }

        it "returns 200 and does NOT send a shortener-branded payment-failed email" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end

      context "invoice.payment_action_required for a LevelCode subscription" do
        let(:invoice) { build_invoice(customer: user.stripe_id) }
        let(:event)   { build_event("invoice.payment_action_required", invoice) }

        before { allow(Stripe::Subscription).to receive(:retrieve).and_return(levelcode_sub) }

        it "returns 200 and does NOT send a shortener-branded action-required email" do
          post_stripe_webhook(event)
          expect(response).to have_http_status(:ok)
          expect(ActionMailer::Base.deliveries).to be_empty
        end
      end
    end

    # ── Unknown / unregistered event type ───────────────────────────────────

    describe "an unknown event type" do
      let(:obj)   { double("obj") }
      let(:event) { build_event("customer.source.created", obj) }

      it "returns 200" do
        post_stripe_webhook(event)
        expect(response).to have_http_status(:ok)
      end

      it "does not send any email" do
        post_stripe_webhook(event)
        expect(ActionMailer::Base.deliveries).to be_empty
      end

      it "still records the event as processed" do
        expect { post_stripe_webhook(event) }
          .to change(ProcessedStripeEvent, :count).by(1)
      end
    end

    # ── Money-critical sync failure → release idempotency + retry ────────────
    #
    # A LevelCode wallet sync (teardown/provision) that fails AFTER idempotency is claimed must not be
    # silently stranded — the claim is RELEASED and a non-2xx is returned so Stripe retries.
    describe "when the LevelCode wallet sync fails" do
      let(:obj)   { double("obj") }
      let(:event) { build_event("customer.subscription.deleted", obj) }

      before do
        allow(Levelcode::WebhookSync).to receive(:call)
          .and_raise(ActiveRecord::StatementInvalid, "connection lost")
      end

      it "returns a non-2xx so Stripe retries" do
        post_stripe_webhook(event)
        expect(response).to have_http_status(:internal_server_error)
      end

      it "releases the idempotency claim so the retry re-runs the sync" do
        expect { post_stripe_webhook(event) }
          .not_to change(ProcessedStripeEvent, :count) # claimed then released → net zero
        expect(ProcessedStripeEvent.exists?(stripe_event_id: event.id)).to be(false)
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
