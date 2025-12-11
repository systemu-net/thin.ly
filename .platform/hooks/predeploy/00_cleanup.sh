#!/usr/bin/env bash
set -e

echo "=== Cleaning up any stuck processes ==="

# Kill any hung Sidekiq processes
pkill -9 sidekiq || true

# Kill any stuck bundle processes
pkill -9 -f "bundle exec" || true

# Remove stale PID files
rm -f /var/app/support/pids/sidekiq.pid || true
rm -f /var/app/current/tmp/pids/*.pid || true

# Stop systemd service if it exists
systemctl stop sidekiq 2>/dev/null || true

echo "✓ Cleanup complete"
