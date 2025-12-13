#!/usr/bin/env bash
set -e

echo "=== Starting Sidekiq via systemd ==="

# Reload systemd in case service file changed
systemctl daemon-reload

# Start Sidekiq service
echo "Starting Sidekiq service..."
systemctl start sidekiq

# Wait a moment for Sidekiq to initialize
sleep 3

# Check status
if systemctl is-active --quiet sidekiq; then
  echo "✓ Sidekiq systemd service is running"
  
  # Check if actual Sidekiq process started (not just bash wrapper)
  if pgrep -f "sidekiq.*production" > /dev/null; then
    echo "✓ Sidekiq process is running"
  else
    echo "WARNING: Sidekiq systemd is active but process not detected yet"
    echo "This is normal - Sidekiq may still be starting..."
  fi
  
  systemctl status sidekiq --no-pager || true
else
  echo "WARNING: Sidekiq failed to start"
  systemctl status sidekiq --no-pager || true
  journalctl -u sidekiq -n 50 --no-pager || true
fi

echo "=== Sidekiq Setup Complete ==="
