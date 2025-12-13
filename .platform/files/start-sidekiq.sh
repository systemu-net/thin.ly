#!/bin/bash
# Wrapper script to set up Ruby environment for Sidekiq

# Change to app directory
cd /var/app/current || exit 1

# Try to source Ruby environment setup if it exists
if [ -f /opt/elasticbeanstalk/bin/use-app-ruby.sh ]; then
  source /opt/elasticbeanstalk/bin/use-app-ruby.sh
elif [ -f /opt/elasticbeanstalk/support/scripts/use-app-ruby.sh ]; then
  source /opt/elasticbeanstalk/support/scripts/use-app-ruby.sh
fi

# Alternatively, just ensure bundler is in PATH
export PATH="/var/app/current/bin:$PATH"

# Load environment variables
if [ -f /opt/elasticbeanstalk/deployment/env ]; then
  set -a
  source /opt/elasticbeanstalk/deployment/env
  set +a
fi

# Start Sidekiq
exec bundle exec sidekiq -e production -C config/sidekiq.yml
