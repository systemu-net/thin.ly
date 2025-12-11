#!/usr/bin/env bash
set -e

echo "=== Starting Sidekiq Setup ==="

# Try to get config, fallback to standard paths if not available
EB_APP_DEPLOY_DIR=$(/opt/elasticbeanstalk/bin/get-config container -k app_deploy_dir 2>/dev/null || echo "/var/app/current")
EB_APP_PID_DIR=$(/opt/elasticbeanstalk/bin/get-config container -k app_pid_dir 2>/dev/null || echo "/var/app/support/pids")
EB_APP_USER=$(/opt/elasticbeanstalk/bin/get-config container -k app_user 2>/dev/null || echo "webapp")
EB_SCRIPT_DIR=$(/opt/elasticbeanstalk/bin/get-config container -k script_dir 2>/dev/null || echo "/opt/elasticbeanstalk/bin")
EB_SUPPORT_DIR=$(/opt/elasticbeanstalk/bin/get-config container -k support_dir 2>/dev/null || echo "/opt/elasticbeanstalk/support")

echo "App directory: $EB_APP_DEPLOY_DIR"
echo "PID directory: $EB_APP_PID_DIR"
echo "App user: $EB_APP_USER"

# Source environment variables if files exist
[ -f "$EB_SUPPORT_DIR/envvars" ] && . $EB_SUPPORT_DIR/envvars
[ -f "$EB_SCRIPT_DIR/use-app-ruby.sh" ] && . $EB_SCRIPT_DIR/use-app-ruby.sh

# Sidekiq configuration
SIDEKIQ_PID="$EB_APP_PID_DIR/sidekiq.pid"
SIDEKIQ_CONFIG="$EB_APP_DEPLOY_DIR/config/sidekiq.yml"
SIDEKIQ_LOG="$EB_APP_DEPLOY_DIR/log/sidekiq.log"

# Ensure directories exist
mkdir -p "$EB_APP_PID_DIR"
mkdir -p "$EB_APP_DEPLOY_DIR/log"

cd $EB_APP_DEPLOY_DIR

# Check if Redis is available
echo "Checking Redis connectivity..."
if ! bundle exec ruby -e "require 'redis'; Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0').ping" 2>/dev/null; then
  echo "WARNING: Redis is not available. Skipping Sidekiq start."
  logger -t "sidekiq" "WARNING: Redis is not available"
  exit 0
fi

echo "✓ Redis is available"

# Stop existing Sidekiq process
if [ -f "$SIDEKIQ_PID" ]; then
  OLD_PID=$(cat $SIDEKIQ_PID)
  if ps -p $OLD_PID > /dev/null 2>&1; then
    echo "Stopping existing Sidekiq (PID: $OLD_PID)"
    logger -t "sidekiq" "Stopping Sidekiq (PID: $OLD_PID)"
    
    su -s /bin/bash -c "kill -TERM $OLD_PID" $EB_APP_USER 2>/dev/null || true
    
    # Wait up to 30 seconds
    for i in {1..30}; do
      if ! ps -p $OLD_PID > /dev/null 2>&1; then
        echo "✓ Sidekiq stopped gracefully"
        break
      fi
      sleep 1
    done
    
    # Force kill if needed
    if ps -p $OLD_PID > /dev/null 2>&1; then
      echo "Force stopping Sidekiq"
      su -s /bin/bash -c "kill -9 $OLD_PID" $EB_APP_USER 2>/dev/null || true
    fi
  fi
  rm -f "$SIDEKIQ_PID"
fi

sleep 3

# Start Sidekiq
echo "Starting Sidekiq..."
logger -t "sidekiq" "Starting Sidekiq in ${RACK_ENV:-production} environment"

# Sidekiq 8.0 removed -L and -P options, manage PID manually
# Use setsid to fully detach the process and avoid hanging
su -s /bin/bash $EB_APP_USER << EOF
cd $EB_APP_DEPLOY_DIR
setsid bundle exec sidekiq -e ${RACK_ENV:-production} -C $SIDEKIQ_CONFIG >> $SIDEKIQ_LOG 2>&1 &
echo \$! > $SIDEKIQ_PID
EOF

# Brief wait for PID file creation
sleep 2

# Verify Sidekiq started (but don't fail deployment if it didn't)
if [ -f "$SIDEKIQ_PID" ]; then
  NEW_PID=$(cat $SIDEKIQ_PID)
  if ps -p $NEW_PID > /dev/null 2>&1; then
    echo "✓ Sidekiq started successfully (PID: $NEW_PID)"
    logger -t "sidekiq" "SUCCESS: Sidekiq started (PID: $NEW_PID)"
  else
    echo "WARNING: Sidekiq PID file exists but process not found"
    logger -t "sidekiq" "WARNING: Sidekiq process not running after start"
    cat "$SIDEKIQ_LOG" 2>/dev/null | tail -20 || true
  fi
else
  echo "WARNING: Sidekiq PID file not created yet"
  logger -t "sidekiq" "WARNING: PID file not created"
  cat "$SIDEKIQ_LOG" 2>/dev/null | tail -20 || true
fi

echo "=== Sidekiq Setup Complete ==="
exit 0