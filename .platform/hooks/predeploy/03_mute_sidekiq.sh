#!/usr/bin/env bash
set -e

# Use fixed paths since app isn't deployed yet
EB_APP_USER="webapp"
SIDEKIQ_PID="/var/app/support/pids/sidekiq.pid"

if [ -f $SIDEKIQ_PID ]; then
  PID=$(cat $SIDEKIQ_PID)
  echo "Sending USR1 to Sidekiq (PID: $PID) to stop processing new jobs"
  logger -t "sidekiq" "Sending USR1 to Sidekiq (PID: $PID)"
  su -s /bin/bash -c "kill -USR1 $PID" $EB_APP_USER 2>/dev/null || true
  echo "Sidekiq will finish current jobs before shutdown"
else
  echo "No Sidekiq PID file found, nothing to quiet"
fi