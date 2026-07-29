# frozen_string_literal: true

require "set"

# Reconciliation for Stripe customers that no `users` row points at.
#
# WHY THEY EXIST: `User#create_stripe_customer` used to hang off `before_validation,
# on: :create`, which fires even when the record is about to be REJECTED. So every
# failed signup still minted a real Stripe customer and then threw away the user.
# The LevelCode Google flow did exactly that on EVERY new account — it called
# `User.from_google` without `terms_accepted:`, tripping the `on: :create` acceptance
# validation — until the fix in `Levelcode::ProviderOAuth#google_user`. The callback
# has since moved to `before_create`, so the leak is closed going forward; this task
# is for the customers already stranded in Stripe.
#
# `report` is READ-ONLY and is the entry point. `delete` exists but refuses to run
# without an explicit, per-run confirmation — read the report first, decide what is
# genuinely disposable, and only then hand those ids back.
#
#   bundle exec rake stripe:orphans:report
#   bundle exec rake stripe:orphans:report SINCE=2026-07-22 UNTIL=2026-07-29
#   bundle exec rake stripe:orphans:delete MANIFEST=tmp/... CLASSES=ORPHAN_RETRY CONFIRM=DELETE
#
namespace :stripe do
  namespace :orphans do
    # The LevelCode Google auth-code flow could not have produced a customer before
    # this date: until `ecace42` (2026-07-22) the authorize URL was built with
    # ENV["GOOGLE_OAUTH_ID"], which was never set in the environment, so Google
    # rejected the request and the callback that creates users never ran. The report
    # prints the empirically observed first failure from `auth_events` too — trust
    # that over this constant if they disagree.
    DEFAULT_SINCE = "2026-07-22"

    # A signup in flight has a live Stripe customer and no committed `users` row yet.
    # Ignore anything this recent so a concurrent signup is never called an orphan.
    DEFAULT_SKEW_MINUTES = 60

    # The whole report is a comparison between "customers in Stripe" and "customers
    # this database knows about", so pointing a LIVE Stripe key at a non-production
    # database does not degrade gracefully — every real customer is missing from the
    # dev/staging `users` table and the report calls all of them orphans. Refuse.
    def guard_live_key!
      abort("Stripe.api_key is not set — run this where the app's credentials are.") if Stripe.api_key.blank?
      return unless Stripe.api_key.to_s.start_with?("sk_live")
      return if Rails.env.production?
      return if ENV["ALLOW_LIVE_OUTSIDE_PRODUCTION"] == "1"

      abort(<<~MSG)
        Refusing to run: LIVE Stripe key in the #{Rails.env} environment.

        This task compares Stripe against THIS database's users table. With a live key
        and a non-production database, every production customer looks like an orphan.
        Run it on production, or set ALLOW_LIVE_OUTSIDE_PRODUCTION=1 if you have
        genuinely pointed this process at the production database.
      MSG
    end

    desc "Report Stripe customers with no matching users row (READ-ONLY, deletes nothing)"
    task report: :environment do
      guard_live_key!

      since  = (ENV["SINCE"].presence || DEFAULT_SINCE).then { |s| Time.zone.parse(s) or abort("Bad SINCE=#{s}") }
      until_ = ENV["UNTIL"].present? ? (Time.zone.parse(ENV["UNTIL"]) or abort("Bad UNTIL")) : Time.current
      skew   = (ENV["SKEW_MINUTES"].presence || DEFAULT_SKEW_MINUTES).to_i.minutes
      cutoff = [ until_, Time.current - skew ].min

      puts "Stripe orphan reconciliation"
      puts "  window   : #{since.iso8601} .. #{cutoff.iso8601}"
      puts "  skew     : ignoring customers created in the last #{skew.inspect}"
      puts "  stripe   : #{Stripe.api_key.to_s.start_with?('sk_live') ? 'LIVE' : 'TEST'} key, api #{Stripe.api_version}"
      puts

      # ---- What the corroborating evidence says --------------------------------
      # The OAuth callback logs a failure event per rejected signup. It does NOT
      # record the email (by that point `google_user` has returned an unsaved record
      # and the controller never sees one), so these cannot be joined to customers —
      # but the COUNT and the time span are an independent check on the orphan set.
      # If the two numbers are wildly apart, stop and work out why before deleting.
      failures = AuthEvent.where(kind: "oauth", provider: "google", outcome: "failure", reason: "oauth_failed")
                          .where(created_at: since..cutoff)
      puts "auth_events corroboration (kind=oauth provider=google outcome=failure):"
      puts "  failed google signups in window : #{failures.count}"
      puts "  first / last                    : #{failures.minimum(:created_at)&.iso8601 || '—'}" \
           " / #{failures.maximum(:created_at)&.iso8601 || '—'}"
      puts "  NOTE: these rows carry no email, so they corroborate the count, not the identity."
      puts

      # ---- Every customer id the database still claims -------------------------
      # Both columns: `levelcode_stripe_id` is not written by any code path today,
      # but the column and its unique index exist, so a backfill or a console session
      # could have populated it. Cheap insurance against deleting a live customer.
      known = Set.new
      User.find_in_batches(batch_size: 5_000) do |batch|
        batch.each do |u|
          known << u.stripe_id if u.stripe_id.present?
          known << u.levelcode_stripe_id if u.levelcode_stripe_id.present?
        end
      end
      puts "users rows referencing a Stripe customer: #{known.size}"
      puts

      # ---- Candidates ----------------------------------------------------------
      candidates = []
      scanned = 0
      Stripe::Customer.list({ created: { gte: since.to_i, lte: cutoff.to_i }, limit: 100 }).auto_paging_each do |c|
        scanned += 1
        next if known.include?(c.id)

        candidates << c
      end
      puts "scanned #{scanned} Stripe customers in window; #{candidates.size} have no users row."
      puts

      if candidates.empty?
        puts "Nothing to reconcile."
        next
      end

      # An email that still belongs to a user is the strongest signal available: the
      # person was rejected, retried, and eventually got an account — so the customer
      # left behind is provably the discarded one, not somebody's live billing record.
      #
      # Map email -> every customer id that account actually references, across BOTH
      # columns and dropping blanks. The empty array is a distinct, meaningful case: an
      # account that exists but references NO Stripe customer is not evidence that this
      # customer is the discarded duplicate — there is no "other" customer to be the
      # live one — so it must not reach ORPHAN_RETRY, the class `delete` acts on.
      emails = candidates.filter_map { |c| c.email.presence&.downcase }.uniq
      users_by_email = User.where(email: emails)
                          .pluck(:email, :stripe_id, :levelcode_stripe_id)
                          .to_h { |mail, sid, lid| [ mail.to_s.downcase, [ sid, lid ].select(&:present?) ] }
      email_counts = candidates.filter_map { |c| c.email.presence&.downcase }.tally

      rows = candidates.map { |c| classify(c, users_by_email, email_counts) }

      # ---- Output --------------------------------------------------------------
      by_class = rows.group_by { |r| r[:classification] }
      puts format("%-22s %-34s %-28s %s", "CLASSIFICATION", "CUSTOMER", "EMAIL", "CREATED")
      puts "-" * 110
      rows.sort_by { |r| [ r[:classification], r[:created] ] }.each do |r|
        puts format("%-22s %-34s %-28s %s", r[:classification], r[:id], r[:email].to_s[0, 27], r[:created].iso8601)
      end
      puts

      puts "Summary:"
      by_class.sort_by { |k, _| k }.each { |k, v| puts format("  %-22s %d", k, v.size) }
      puts
      puts CLASSIFICATION_NOTES
      puts

      out = ENV["OUT"].presence || Rails.root.join("tmp", "stripe_orphans_#{Time.current.to_i}.json").to_s
      FileUtils.mkdir_p(File.dirname(out))
      File.write(out, JSON.pretty_generate(
        generated_at: Time.current.iso8601,
        window: { since: since.iso8601, until: cutoff.iso8601 },
        livemode: Stripe.api_key.to_s.start_with?("sk_live"),
        auth_event_failures: failures.count,
        scanned: scanned,
        candidates: rows.map { |r| r.merge(created: r[:created].iso8601) }
      ))
      puts "Manifest: #{out}"
      puts "Nothing has been deleted. Review the manifest, then see stripe:orphans:delete."
    end

    desc "Delete Stripe customers from a report manifest (requires CONFIRM=DELETE)"
    task delete: :environment do
      guard_live_key!

      manifest = ENV["MANIFEST"].presence or abort("MANIFEST=path/to/manifest.json is required.")
      data = JSON.parse(File.read(manifest), symbolize_names: true)

      # Opt in by classification, so nobody can sweep the whole file by accident.
      # ORPHAN_RETRY is the only class this will accept by default — the one where a
      # live user account proves the customer is the discarded duplicate.
      classes = (ENV["CLASSES"].presence || "ORPHAN_RETRY").split(",").map(&:strip)
      targets = data[:candidates].select { |c| classes.include?(c[:classification]) }
      abort("No candidates in #{manifest} match CLASSES=#{classes.join(',')}") if targets.empty?

      puts "About to DELETE #{targets.size} Stripe customer(s) in classes: #{classes.join(', ')}"
      puts "  manifest generated #{data[:generated_at]} against #{data[:livemode] ? 'LIVE' : 'TEST'} Stripe"
      targets.first(20).each { |t| puts "  #{t[:id]}  #{t[:email]}" }
      puts "  ... and #{targets.size - 20} more" if targets.size > 20
      puts

      unless ENV["CONFIRM"] == "DELETE"
        abort("Refusing to delete. Re-run with CONFIRM=DELETE once you have reviewed the list above.")
      end

      deleted = 0
      skipped = 0
      targets.each do |t|
        # Re-verify against the CURRENT database rather than trusting the manifest.
        # A person rejected during the outage may have signed up successfully in the
        # meantime and been assigned this very customer; the manifest would be stale
        # and deleting it would break a live account.
        if User.where(stripe_id: t[:id]).or(User.where(levelcode_stripe_id: t[:id])).exists?
          puts "SKIP #{t[:id]} — a users row now points at it"
          skipped += 1
          next
        end

        if commercial_activity?(t[:id])
          puts "SKIP #{t[:id]} — has subscriptions/invoices/charges"
          skipped += 1
          next
        end

        Stripe::Customer.delete(t[:id])
        puts "DELETED #{t[:id]}  #{t[:email]}"
        deleted += 1
      rescue Stripe::InvalidRequestError => e
        puts "SKIP #{t[:id]} — Stripe says: #{e.message}"
        skipped += 1
      end

      puts
      puts "Deleted #{deleted}, skipped #{skipped}."
    end

    CLASSIFICATION_NOTES = <<~NOTES
      What the classifications mean:

        ORPHAN_RETRY      No users row points at this customer, but a user EXISTS with the same
                          email and references at least one OTHER Stripe customer (either column).
                          That is the outage signature: rejected, retried, eventually got in, and
                          the live customer is a different one. The safest class to delete.

                          The "references at least one other" half is load-bearing. An account with
                          NO stripe id is not a retry — there is no live customer for this one to be
                          the discard of — so it falls through to UNMATCHED for a human instead.

        ORPHAN_DUPLICATE  Several customers in the window share this email and none is referenced.
                          A burst of retries by one person. Safe, but confirm the email is not a
                          shared/team address first.

        ORPHAN_UNMATCHED  No users row and no user with this email, no commercial activity.
                          PROBABLY an orphan from someone who gave up — but this is also exactly
                          what a legitimately DELETED user looks like, because `dependent: :destroy`
                          takes the subscriptions with it and the after_commit Stripe cleanup is
                          best-effort (it logs and moves on when Stripe errors). Cross-check these
                          against the "[user N] Stripe customer ... was not deleted" warnings in the
                          logs before touching them.

        REVIEW_ACTIVITY   Has a subscription, invoice, charge or payment method. Whatever this is,
                          it is not a signup that never completed. Do not delete from this task.

      A caveat that no classification can fix: thin.ly and LevelCode share ONE Stripe account
      (a single Stripe.api_key) and `Stripe::Customer.create(email:)` writes no metadata, so a
      customer carries nothing saying which product made it. The window is the only separator,
      and it is a coarse one — any thin.ly signup that failed validation in the same window lands
      in this report too. Those are equally orphaned, but they are not the LevelCode outage.
    NOTES

    # Signals that this customer was ever a real, transacting customer. Probing stops
    # at the first hit to keep the API calls down.
    def commercial_activity?(id)
      return true if Stripe::Subscription.list({ customer: id, status: "all", limit: 1 }).data.any?
      return true if Stripe::Invoice.list({ customer: id, limit: 1 }).data.any?
      return true if Stripe::Charge.list({ customer: id, limit: 1 }).data.any?

      Stripe::PaymentMethod.list({ customer: id, limit: 1 }).data.any?
    rescue Stripe::StripeError => e
      # Treat "cannot tell" as "has activity" — the conservative direction, since the
      # only consequence is that a human looks at it.
      warn "  probe failed for #{id}: #{e.class}: #{e.message} — classifying as REVIEW"
      true
    end

    def classify(customer, users_by_email, email_counts)
      email = customer.email.presence&.downcase
      # nil  -> no account with this email at all
      # []   -> an account exists but references no Stripe customer (anomaly, not retry)
      # [..] -> an account exists and references these customers
      account_ids = email ? users_by_email[email] : nil

      row = {
        id: customer.id,
        email: customer.email,
        created: Time.zone.at(customer.created),
        user_with_same_email: !account_ids.nil?,
        user_stripe_ids: account_ids || []
      }

      classification =
        if commercial_activity?(customer.id)
          "REVIEW_ACTIVITY"
        elsif account_ids.present? && account_ids.exclude?(customer.id)
          "ORPHAN_RETRY"
        elsif email && email_counts[email].to_i > 1
          "ORPHAN_DUPLICATE"
        else
          "ORPHAN_UNMATCHED"
        end

      row.merge(classification: classification)
    end
  end
end
