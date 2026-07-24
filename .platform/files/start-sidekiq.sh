#!/bin/bash
# Wrapper script to set up the Ruby environment for Sidekiq.
#
# HISTORY — read before editing. This script used to hardcode
#   PATH=.../vendor/bundle/ruby/3.4.0/bin
# When the Elastic Beanstalk platform moved to Ruby 4.0, that directory stopped existing. Sidekiq then
# resolved through the system gems, where the bundler pinned in Gemfile.lock is absent, and died on
# every boot with:
#   "Could not find 'bundler' (~> 2.5) - did find: [bundler-4.0.10]"
# Puma was unaffected — EB launches it through the platform's own Ruby setup rather than this wrapper —
# so the site stayed up while the usage ledger silently froze for ~27 hours and 141 jobs queued.
#
# Two rules follow: never hardcode a Ruby ABI version here, and never assume the platform's bundler
# matches the one recorded in Gemfile.lock.

set -euo pipefail

cd /var/app/current || exit 1

export RAILS_ENV=production
export RACK_ENV=production
export BUNDLE_GEMFILE=/var/app/current/Gemfile
export BUNDLE_WITHOUT="development:test"

# Adopt the platform's Ruby FIRST, so the vendored bundle selected below matches the interpreter we are
# about to exec.
for ruby_env in /opt/elasticbeanstalk/bin/use-app-ruby.sh /opt/elasticbeanstalk/support/scripts/use-app-ruby.sh; do
  if [ -f "$ruby_env" ]; then
    # shellcheck disable=SC1090
    . "$ruby_env"
    break
  fi
done

# Resolve the vendored bundle for the ABI of the Ruby WE ARE ABOUT TO RUN, not merely the first one on
# disk. A glob alone is not enough: a leftover 3.4.0 directory sitting beside a new 4.0.0 sorts first,
# so we would hand the new interpreter the old gemset and walk straight back into the boot failure this
# script exists to prevent. Ask Ruby for its own ABI, and only fall back to "any present" if that exact
# path is missing (a fallback is still better than the hardcoded version this replaced).
ruby_abi="$(ruby -e 'print RbConfig::CONFIG["ruby_version"]' 2>/dev/null || true)"
bundle_bin=""
if [ -n "$ruby_abi" ] && [ -d "/var/app/current/vendor/bundle/ruby/${ruby_abi}/bin" ]; then
  bundle_bin="/var/app/current/vendor/bundle/ruby/${ruby_abi}/bin"
else
  for candidate in /var/app/current/vendor/bundle/ruby/*/bin; do
    if [ -d "$candidate" ]; then
      bundle_bin="$candidate"
      echo "start-sidekiq: WARNING no bundle for Ruby ABI '${ruby_abi:-unknown}'; falling back to $candidate"
      break
    fi
  done
fi
export PATH="/var/app/current/bin${bundle_bin:+:$bundle_bin}:$PATH"

# The bundler recorded in Gemfile.lock ("BUNDLED WITH") is what `bundle` activates. A platform upgrade
# can ship a different one — exactly the failure above — so install the pinned version on demand rather
# than refusing to boot. --user-install keeps it in the webapp user's GEM_PATH, needing no privileges.
# Best effort: if it fails we still attempt to start, and the postdeploy verifier fails the deploy
# loudly rather than leaving a dead worker behind.
required_bundler="$(awk '/^BUNDLED WITH$/ { getline; gsub(/[[:space:]]/, ""); print; exit }' \
  /var/app/current/Gemfile.lock 2>/dev/null || true)"
if [ -n "$required_bundler" ] && ! gem list -i -v "$required_bundler" bundler >/dev/null 2>&1; then
  echo "start-sidekiq: bundler $required_bundler not installed; installing (--user-install)"
  gem install bundler -v "$required_bundler" --no-document --user-install ||
    echo "start-sidekiq: WARNING could not install bundler $required_bundler; continuing"
fi

# `bundle exec` rather than the bin/sidekiq binstub: the binstub resolves through the pinned bundler,
# which is the brittle path this entire comment is about.
exec bundle exec sidekiq -e production -C config/sidekiq.yml
