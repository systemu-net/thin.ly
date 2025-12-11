#!/usr/bin/env bash
set -e

echo "=== Starting Sidekiq via systemd ==="

# Reload systemd in case service file changed
systemctl daemon-reload

# Start Sidekiq service
echo "Starting Sidekiq service..."
systemctl start sidekiq

# Check status
if systemctl is-active --quiet sidekiq; then
  echo "✓ Sidekiq is running"
  systemctl status sidekiq --no-pager || true
else
  echo "WARNING: Sidekiq failed to start"
  systemctl status sidekiq --no-pager || true
  journalctl -u sidekiq -n 50 --no-pager || true
fi

echo "=== Sidekiq Setup Complete ==="
