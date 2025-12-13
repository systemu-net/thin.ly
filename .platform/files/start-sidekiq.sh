#!/bin/bash
# Wrapper script to set up Ruby environment for Sidekiq

# Exit on error
set -e

# Change to app directory
cd /var/app/current || exit 1

# Set production environment first
export RAILS_ENV=production
export RACK_ENV=production
export BUNDLE_GEMFILE=/var/app/current/Gemfile

# Try to source Ruby environment setup if it exists
if [ -f /opt/elasticbeanstalk/bin/use-app-ruby.sh ]; then
  source /opt/elasticbeanstalk/bin/use-app-ruby.sh
elif [ -f /opt/elasticbeanstalk/support/scripts/use-app-ruby.sh ]; then
  source /opt/elasticbeanstalk/support/scripts/use-app-ruby.sh
fi

# Ensure bundler is in PATH
export PATH="/var/app/current/bin:/var/app/current/vendor/bundle/ruby/3.4.0/bin:$PATH"

# Start Sidekiq
exec bundle exec sidekiq -e production -C config/sidekiq.yml
