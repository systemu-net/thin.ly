#!/usr/bin/env bash
set -e

# Use staging directory in predeploy phase
EB_APP_STAGING_DIR="/var/app/staging"
EB_APP_USER="webapp"

# Ensure log directory exists
mkdir -p $EB_APP_STAGING_DIR/log
touch $EB_APP_STAGING_DIR/log/sidekiq.log
chown -R $EB_APP_USER:$EB_APP_USER $EB_APP_STAGING_DIR/log
chmod 0664 $EB_APP_STAGING_DIR/log/sidekiq.log

echo "Sidekiq log directory setup complete"