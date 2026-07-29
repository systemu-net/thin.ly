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

# Every customer id the database still claims. Both columns — `levelcode_stripe_id` is not
# written by any code path today, but it is uniquely indexed and could have been backfilled.
known = User.pluck(:stripe_id, :levelcode_stripe_id).flatten.compact_blank.to_set

candidates = []
Stripe::Customer.list({ created: { gte: since.to_i, lte: cutoff.to_i }, limit: 100 })
                .auto_paging_each { |c| candidates << c unless known.include?(c.id) }

# email => the customer ids that email's account actually references (blanks dropped).
# nil means no account; [] means an account exists but references no customer at all.
emails   = candidates.filter_map { |c| c.email.presence&.downcase }.uniq
accounts = User.where(email: emails).pluck(:email, :stripe_id, :levelcode_stripe_id)
               .to_h { |m, s, l| [ m.to_s.downcase, [ s, l ].compact_blank ] }
dupes    = candidates.filter_map { |c| c.email.presence&.downcase }.tally

active = lambda do |id|
  Stripe::Subscription.list({ customer: id, status: "all", limit: 1 }).data.any? ||
    Stripe::Invoice.list({ customer: id, limit: 1 }).data.any? ||
    Stripe::Charge.list({ customer: id, limit: 1 }).data.any?
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

puts "failed google signups in window: " \
     "#{AuthEvent.where(kind: 'oauth', provider: 'google', outcome: 'failure', created_at: since..cutoff).count}"
puts "first/last failure: " \
     "#{AuthEvent.where(kind: 'oauth', provider: 'google', outcome: 'failure').minimum(:created_at)} .. " \
     "#{AuthEvent.where(kind: 'oauth', provider: 'google', outcome: 'failure').maximum(:created_at)}"
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

## Step 3 — Delete

Only after step 2. Start from the `RETRY` set, or paste an explicit list of ids you have decided
on. Each deletion is re-checked first: someone rejected during the outage may since have signed up
and been assigned that very customer, which would make the report stale.

```ruby
doomed = report.select { |r| r[:klass] == "RETRY" }.map { |r| r[:id] }
# ...or be explicit:
# doomed = %w[cus_AAA cus_BBB]

puts "about to delete #{doomed.size} customers"

deleted = 0
skipped = 0
doomed.each do |id|
  if User.where(stripe_id: id).or(User.where(levelcode_stripe_id: id)).exists?
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
nil
```

Deleting a Stripe customer is **not reversible**. Re-run step 1 afterwards to confirm the set
is empty.
