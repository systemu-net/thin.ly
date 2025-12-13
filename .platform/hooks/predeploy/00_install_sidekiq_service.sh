#!/usr/bin/env bash
set -e

echo "=== Installing Sidekiq systemd service ==="

SERVICE_FILE="/var/app/current/.platform/files/sidekiq.service"
SYSTEMD_FILE="/etc/systemd/system/sidekiq.service"

# Stop service if running with old config
systemctl stop sidekiq 2>/dev/null || true

if [ -f "$SERVICE_FILE" ]; then
  echo "Copying service file to systemd..."
  cp "$SERVICE_FILE" "$SYSTEMD_FILE"
  chmod 644 "$SYSTEMD_FILE"
  
  echo "Reloading systemd daemon..."
  systemctl daemon-reload
  
  echo "Enabling Sidekiq service..."
  systemctl enable sidekiq
  
  # Reset failed state if any
  systemctl reset-failed sidekiq 2>/dev/null || true
  
  echo "✓ Sidekiq service installed and enabled"
else
  echo "WARNING: Service file not found at $SERVICE_FILE"
fi
