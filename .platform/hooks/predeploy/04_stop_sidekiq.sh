#!/usr/bin/env bash
set -e

# Use fixed paths since app isn't deployed yet
EB_APP_USER="webapp"
SIDEKIQ_PID="/var/app/support/pids/sidekiq.pid"

if [ -f $SIDEKIQ_PID ]; then
  PID=$(cat $SIDEKIQ_PID)
  echo "Stopping Sidekiq (PID: $PID) before deployment"
  logger -t "sidekiq" "Stopping Sidekiq (PID: $PID)"
  
  # Graceful shutdown
  su -s /bin/bash -c "kill -TERM $PID" $EB_APP_USER 2>/dev/null || true
  
  # Wait for shutdown (up to 60 seconds)
  for i in {1..60}; do
    if ! ps -p $PID > /dev/null 2>&1; then
      echo "Sidekiq stopped successfully"
      logger -t "sidekiq" "Sidekiq stopped successfully"
      rm -f $SIDEKIQ_PID
      exit 0
    fi
    sleep 1
  done
  
  # Force kill if still running
  echo "Force stopping Sidekiq after timeout"
  logger -t "sidekiq" "Force stopping Sidekiq after timeout"
  su -s /bin/bash -c "kill -9 $PID" $EB_APP_USER 2>/dev/null || true
  rm -f $SIDEKIQ_PID
else
  echo "No Sidekiq process to stop"
fi