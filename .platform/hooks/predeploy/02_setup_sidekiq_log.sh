#!/usr/bin/env bash
set -e

EB_APP_DEPLOY_DIR=$(/opt/elasticbeanstalk/bin/get-config container -k app_deploy_dir)
EB_APP_USER=$(/opt/elasticbeanstalk/bin/get-config container -k app_user)

# Ensure log directory exists
mkdir -p $EB_APP_DEPLOY_DIR/log
touch $EB_APP_DEPLOY_DIR/log/sidekiq.log
chown -R $EB_APP_USER:$EB_APP_USER $EB_APP_DEPLOY_DIR/log
chmod 0664 $EB_APP_DEPLOY_DIR/log/sidekiq.log

echo "Sidekiq log directory setup complete"