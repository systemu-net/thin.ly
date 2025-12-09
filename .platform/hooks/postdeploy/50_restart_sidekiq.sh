#!/usr/bin/env bash
set -e

# Get Elastic Beanstalk environment variables
EB_APP_DEPLOY_DIR=$(/opt/elasticbeanstalk/bin/get-config container -k app_deploy_dir)
EB_APP_PID_DIR=$(/opt/elasticbeanstalk/bin/get-config container -k app_pid_dir)
EB_APP_USER=$(/opt/elasticbeanstalk/bin/get-config container -k app_user)
EB_SCRIPT_DIR=$(/opt/elasticbeanstalk/bin/get-config container -k script_dir)
EB_SUPPORT_DIR=$(/opt/elasticbeanstalk/bin/get-config container -k support_dir)

# Source environment variables
. $EB_SUPPORT_DIR/envvars
. $EB_SCRIPT_DIR/use-app-ruby.sh

# Sidekiq configuration
SIDEKIQ_PID=$EB_APP_PID_DIR/sidekiq.pid
SIDEKIQ_CONFIG=$EB_APP_DEPLOY_DIR/config/sidekiq.yml
SIDEKIQ_LOG=$EB_APP_DEPLOY_DIR/log/sidekiq.log

cd $EB_APP_DEPLOY_DIR

# Check if Redis is available before starting Sidekiq
echo "Checking Redis connectivity..."
if ! bundle exec ruby -e "require 'redis'; Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0').ping" 2>/dev/null; then
  echo "ERROR: Redis is not available. Skipping Sidekiq start."
  logger -t "sidekiq" "ERROR: Redis is not available. Skipping Sidekiq start."
  echo "Please set up ElastiCache and configure REDIS_URL environment variable."
  exit 0  # Exit gracefully, don't fail deployment
fi

echo "Redis is available ✓"

# Stop existing Sidekiq process gracefully
if [ -f $SIDEKIQ_PID ]; then
  OLD_PID=$(cat $SIDEKIQ_PID)
  echo "Stopping existing Sidekiq process (PID: $OLD_PID)"
  logger -t "sidekiq" "Stopping existing Sidekiq process (PID: $OLD_PID)"
  
  # Send TERM signal for graceful shutdown
  su -s /bin/bash -c "kill -TERM $OLD_PID" $EB_APP_USER || true
  
  # Wait up to 30 seconds for graceful shutdown
  for i in {1..30}; do
    if ! ps -p $OLD_PID > /dev/null 2>&1; then
      echo "Sidekiq stopped gracefully"
      logger -t "sidekiq" "Sidekiq stopped gracefully"
      break
    fi
    sleep 1
  done
  
  # Force kill if still running
  if ps -p $OLD_PID > /dev/null 2>&1; then
    echo "Forcing Sidekiq to stop"
    logger -t "sidekiq" "Forcing Sidekiq to stop"
    su -s /bin/bash -c "kill -9 $OLD_PID" $EB_APP_USER || true
  fi
  
  # Clean up PID file
  su -s /bin/bash -c "rm -f $SIDEKIQ_PID" $EB_APP_USER
fi

# Wait a bit before starting new process
sleep 5

# Start Sidekiq
echo "Starting Sidekiq in $RACK_ENV environment..."
logger -t "sidekiq" "Starting Sidekiq in $RACK_ENV environment"

su -s /bin/bash -c "cd $EB_APP_DEPLOY_DIR && bundle exec sidekiq \
  -e $RACK_ENV \
  -C $SIDEKIQ_CONFIG \
  -L $SIDEKIQ_LOG \
  -P $SIDEKIQ_PID \
  -d" $EB_APP_USER

# Verify Sidekiq started
sleep 2
if [ -f $SIDEKIQ_PID ]; then
  NEW_PID=$(cat $SIDEKIQ_PID)
  if ps -p $NEW_PID > /dev/null 2>&1; then
    echo "✓ Sidekiq started successfully (PID: $NEW_PID)"
    logger -t "sidekiq" "Sidekiq started successfully (PID: $NEW_PID)"
  else
    echo "ERROR: Sidekiq failed to start"
    logger -t "sidekiq" "ERROR: Sidekiq failed to start"
    exit 1
  fi
else
  echo "ERROR: Sidekiq PID file not created"
  logger -t "sidekiq" "ERROR: Sidekiq PID file not created"
  exit 1
fi