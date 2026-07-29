# Stripe Orphan Customer Cleanup

## Overview

`User#create_stripe_customer` used to run on `before_validation, on: :create`, which fires even
when the record is about to be **rejected**. Every failed signup therefore created a real,
billable Stripe customer and then threw the user away, leaving a customer with no `users` row
pointing at it.

Two fixes closed it, both shipped in **#404**:

- `Levelcode::ProviderOAuth#google_user` now passes `terms_accepted: true` (#403). While it did
  not, the LevelCode Google flow was rejected by the `terms_accepted` acceptance validation on
  **every** new signup and minted one orphan per attempt.
- The callback moved to `before_create`, so no rejected create reaches Stripe at all.

This is a **one-time** cleanup of the customers stranded before those shipped. It is run by hand
from the Rails console — there is deliberately no rake task, because it should never run twice.

**Affected window:** roughly **2026-07-22** (the LevelCode Google flow could not complete before
this — the authorize URL was built from an unset `GOOGLE_OAUTH_ID` until then) through the #404
deploy. Step 1 prints the observed first/last failure so you can check that date rather than
trust it.

## Getting a production console

Elastic Beanstalk installs the bundle without the dev/test groups, so a bare `bundle exec` fails
with `Could not find rspec-core… Run bundle install`. **Do not run `bundle install` on the
instance** — it would pull rubocop, rspec and brakeman onto a production box. Set `BUNDLE_WITHOUT`
instead. This mirrors `.platform/files/start-sidekiq.sh`, which is the known-good way to run Ruby
on that host:

```bash
sudo -u webapp bash -c 'set -a; . /opt/elasticbeanstalk/deployment/env; set +a; cd /var/app/current; export RAILS_ENV=production RACK_ENV=production BUNDLE_GEMFILE=/var/app/current/Gemfile BUNDLE_WITHOUT="development:test"; for f in /opt/elasticbeanstalk/bin/use-app-ruby.sh /opt/elasticbeanstalk/support/scripts/use-app-ruby.sh; do [ -f "$f" ] && . "$f" && break; done; bundle exec rails console'
```

Each piece matters: `deployment/env` carries `STRIPE_SECRET_KEY` and the database credentials
(a bare SSH shell has neither), `RAILS_ENV=production` selects the right database, and
`use-app-ruby.sh` picks the platform Ruby whose ABI matches the vendored bundle.

**Run both steps in the same console session** — step 2 uses variables from step 1.

## Step 1 — Report (read-only)

Paste this whole block. It deletes nothing.

```ruby
since  = Time.zone.parse("2026-07-22")
cutoff = 1.hour.ago   # ignore in-flight signups: they have a customer, not yet a committed row

# Which columns actually hold a Stripe customer id, asked of the database rather than
# assumed. `levelcode_stripe_id` is in db/schema.rb but NOT in production — it was added
# to the schema by an annotate run with no migration behind it, so databases built by
# `db:schema:load` (development, test) have it and production does not. Asking
# `column_names` makes this block correct on both.
id_cols = User.column_names & %w[stripe_id levelcode_stripe_id]
puts "matching on: #{id_cols.join(', ')}"

# Every customer id the database still claims. Batched, so a large users table does not
# land in console memory all at once.
known = Set.new
User.in_batches(of: 10_000) do |batch|
  known.merge(batch.pluck(*id_cols).flatten.compact_blank)
end

candidates = []
Stripe::Customer.list({ created: { gte: since.to_i, lte: cutoff.to_i }, limit: 100 })
                .auto_paging_each { |c| candidates << c unless known.include?(c.id) }

# email => the customer ids that email's account actually references (blanks dropped).
# nil means no account; [] means an account exists but references no customer at all.
emails   = candidates.filter_map { |c| c.email.presence&.downcase }.uniq
accounts = User.where(email: emails).pluck(:email, *id_cols)
               .to_h { |mail, *ids| [ mail.to_s.downcase, ids.compact_blank ] }
dupes    = candidates.filter_map { |c| c.email.presence&.downcase }.tally

# Any sign this was ever a real, transacting customer. A saved payment method counts:
# someone who entered card details is not a signup that never completed.
# A Stripe error means "cannot tell", which resolves to `true` — the conservative
# direction, since the only cost is that a human looks at it.
active = lambda do |id|
  Stripe::Subscription.list({ customer: id, status: "all", limit: 1 }).data.any? ||
    Stripe::Invoice.list({ customer: id, limit: 1 }).data.any? ||
    Stripe::Charge.list({ customer: id, limit: 1 }).data.any? ||
    Stripe::PaymentMethod.list({ customer: id, limit: 1 }).data.any?
rescue Stripe::StripeError => e
  puts "  probe failed for #{id} (#{e.class}: #{e.message}) — treating as active"
  true
end

report = candidates.map do |c|
  email = c.email.presence&.downcase
  ids   = email ? accounts[email] : nil
  klass = if active.call(c.id) then "REVIEW_ACTIVITY"
          elsif ids.present? && ids.exclude?(c.id) then "RETRY"
          else "UNMATCHED"
          end
  { id: c.id, email: c.email, created: Time.zone.at(c.created), dupes: dupes[email].to_i, klass: klass }
end

# `reason` matters: only `oauth_failed` reached the code that creates a customer.
# `session_expired` returns at the state check, before `google_user` is ever called,
# so counting it would inflate the corroboration against real orphans.
failures = AuthEvent.where(kind: "oauth", provider: "google",
                           outcome: "failure", reason: "oauth_failed")

puts "failed google signups in window: #{failures.where(created_at: since..cutoff).count}"
# Deliberately NOT limited to the window — the point is to see whether failures begin
# before `since`, which a windowed query could never tell you.
puts "first/last failure, all time: " \
     "#{failures.minimum(:created_at)} .. #{failures.maximum(:created_at)}"
puts "candidates: #{report.size}"
report.group_by { |r| r[:klass] }.each { |k, v| puts "  #{k}: #{v.size}" }
report.sort_by { |r| [ r[:klass], r[:created] ] }.each do |r|
  puts "#{r[:klass].ljust(16)} #{r[:id].ljust(22)} #{r[:email].to_s.ljust(30)} #{r[:created]} dupes=#{r[:dupes]}"
end
nil
```

## Step 2 — Review before deleting

| Class | Meaning | Delete? |
| --- | --- | --- |
| `RETRY` | An account exists with this email and references a **different** Stripe customer. The outage signature: rejected, retried, eventually got in — so this one is the discard. | Yes, safest |
| `UNMATCHED` | No account, or an account referencing no customer at all. Probably an orphan from someone who gave up — but this is also exactly what a legitimately **deleted** user looks like. | Only case by case |
| `REVIEW_ACTIVITY` | Has a subscription, invoice or charge. Not a signup that failed. | No |

`dupes=N` counts how many candidates share that email. A high number is a retry burst by one
person, which corroborates `RETRY`.

Two checks worth making before you delete anything:

1. **Does the failure count roughly match the candidate count?** They will not match exactly, but
   an order-of-magnitude gap means something other than this outage is producing orphans, and it
   is worth understanding first.
2. **Does the first failure timestamp agree with `2026-07-22`?** If failures start meaningfully
   earlier, widen `since` and re-run step 1.

Two limits no amount of classification fixes:

- thin.ly and LevelCode share **one** Stripe account, and `Stripe::Customer.create(email:)` writes
  no metadata, so nothing on a customer says which product created it. The time window is the only
  separator — thin.ly signups that failed validation in the same window appear here too. They are
  equally orphaned, but they are not this outage.
- The `auth_events` failure rows carry **no email** (the OAuth callback has no user by then), so
  they corroborate the count and time span, not which customers are which.
- `levelcode_stripe_id` is in `db/schema.rb` and in the model annotations but **does not exist in
  the production database**. It was introduced by an annotate run (`b7b2cfc`) with no migration
  behind it, so databases built by `db:schema:load` have it while production, built by migrations,
  never did — and `db:migrate` will not create it, because nothing defines it. Step 1 asks
  `User.column_names` instead of assuming, and prints which columns it matched on. Worth fixing
  separately: either add a real migration or drop it from the schema.

## Step 3 — Delete

Only after step 2. Start from the `RETRY` set, or paste an explicit list of ids you have decided
on. Each deletion is re-checked first: someone rejected during the outage may since have signed up
and been assigned that very customer, which would make the report stale.

**This block is disarmed as written.** Paste it, read the count it refuses with, then set
`expected` to that number and paste again. Pasting once cannot delete anything, and if the figure
does not match what you reviewed in step 2, the mismatch is the point — re-run step 1 rather than
raising the number to match.

```ruby
doomed = report.select { |r| r[:klass] == "RETRY" }.map { |r| r[:id] }
# ...or be explicit:
# doomed = %w[cus_AAA cus_BBB]

expected = nil   # <- set to the number below to arm this block

if expected != doomed.size
  puts "REFUSING: #{doomed.size} customers queued. Set `expected = #{doomed.size}` to arm."
else

deleted = 0
skipped = 0
doomed.each do |id|
  if id_cols.any? { |col| User.where(col => id).exists? }
    puts "SKIP #{id} — a user now points at it"
    skipped += 1
    next
  end
  if active.call(id)
    puts "SKIP #{id} — has subscriptions/invoices/charges"
    skipped += 1
    next
  end

  Stripe::Customer.delete(id)
  puts "DELETED #{id}"
  deleted += 1
rescue Stripe::InvalidRequestError => e
  puts "SKIP #{id} — #{e.message}"
  skipped += 1
end

puts "deleted #{deleted}, skipped #{skipped}"
end
nil
```

Deleting a Stripe customer is **not reversible**. Re-run step 1 afterwards to confirm the set
is empty.
