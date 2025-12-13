#!/usr/bin/env bash
set -e

echo "=== Installing Sidekiq systemd service ==="

SERVICE_FILE="/var/app/current/.platform/files/sidekiq.service"
WRAPPER_SCRIPT="/var/app/current/.platform/files/start-sidekiq.sh"
SYSTEMD_FILE="/etc/systemd/system/sidekiq.service"

# Stop and disable old service completely
echo "Stopping and disabling old Sidekiq service..."
systemctl stop sidekiq 2>/dev/null || true
systemctl disable sidekiq 2>/dev/null || true
systemctl reset-failed sidekiq 2>/dev/null || true

# Remove old service file to force fresh install
rm -f "$SYSTEMD_FILE"

# Make wrapper script executable
if [ -f "$WRAPPER_SCRIPT" ]; then
  echo "Setting up Sidekiq wrapper script..."
  chmod 755 "$WRAPPER_SCRIPT"
  chown webapp:webapp "$WRAPPER_SCRIPT"
  ls -la "$WRAPPER_SCRIPT"
else
  echo "ERROR: Wrapper script not found at $WRAPPER_SCRIPT"
  exit 1
fi

if [ -f "$SERVICE_FILE" ]; then
  echo "Installing fresh service file..."
  cp "$SERVICE_FILE" "$SYSTEMD_FILE"
  chmod 644 "$SYSTEMD_FILE"
  
  echo "Reloading systemd daemon..."
  systemctl daemon-reload
  
  echo "Enabling Sidekiq service..."
  systemctl enable sidekiq
  
  echo "✓ Sidekiq service installed and enabled"
  echo "Service file contents:"
  cat "$SYSTEMD_FILE"
else
  echo "WARNING: Service file not found at $SERVICE_FILE"
fi
