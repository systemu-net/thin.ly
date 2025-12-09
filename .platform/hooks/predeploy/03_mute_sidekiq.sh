#!/usr/bin/env bash
set -e

SIDEKIQ_PID="/var/app/support/pids/sidekiq.pid"

if [ -f "$SIDEKIQ_PID" ]; then
  PID=$(cat $SIDEKIQ_PID)
  if ps -p $PID > /dev/null 2>&1; then
    echo "Quieting Sidekiq (PID: $PID)"
    logger -t "sidekiq" "Sending USR1 to Sidekiq (PID: $PID)"
    kill -USR1 $PID 2>/dev/null || true
    echo "✓ Sidekiq will finish current jobs"
  fi
else
  echo "No Sidekiq PID file found"
fi