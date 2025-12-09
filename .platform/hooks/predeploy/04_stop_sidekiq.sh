#!/usr/bin/env bash
set -e

SIDEKIQ_PID="/var/app/support/pids/sidekiq.pid"

if [ -f "$SIDEKIQ_PID" ]; then
  PID=$(cat $SIDEKIQ_PID)
  if ps -p $PID > /dev/null 2>&1; then
    echo "Stopping Sidekiq (PID: $PID)"
    logger -t "sidekiq" "Stopping Sidekiq before deployment"
    
    kill -TERM $PID 2>/dev/null || true
    
    # Wait for graceful shutdown
    for i in {1..60}; do
      if ! ps -p $PID > /dev/null 2>&1; then
        echo "✓ Sidekiq stopped gracefully"
        rm -f "$SIDEKIQ_PID"
        exit 0
      fi
      sleep 1
    done
    
    # Force kill if needed
    echo "Force stopping Sidekiq"
    kill -9 $PID 2>/dev/null || true
    rm -f "$SIDEKIQ_PID"
  fi
else
  echo "No Sidekiq process to stop"
fi