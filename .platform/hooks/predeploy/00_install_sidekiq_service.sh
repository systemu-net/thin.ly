#!/usr/bin/env bash
set -e

echo "=== Installing Sidekiq systemd service ==="

APP_STAGING="/var/app/staging"
APP_CURRENT="/var/app/current"

SERVICE_FILE_STAGING="$APP_STAGING/.platform/files/sidekiq.service"
SERVICE_FILE_CURRENT="$APP_CURRENT/.platform/files/sidekiq.service"
WRAPPER_SCRIPT_STAGING="$APP_STAGING/.platform/files/start-sidekiq.sh"
WRAPPER_SCRIPT_CURRENT="$APP_CURRENT/.platform/files/start-sidekiq.sh"

if [ -f "$SERVICE_FILE_STAGING" ] && [ -f "$WRAPPER_SCRIPT_STAGING" ]; then
  SOURCE_ROOT="$APP_STAGING"
elif [ -f "$SERVICE_FILE_CURRENT" ] && [ -f "$WRAPPER_SCRIPT_CURRENT" ]; then
  SOURCE_ROOT="$APP_CURRENT"
else
  echo "ERROR: Could not find both sidekiq.service and start-sidekiq.sh in staging or current."
  echo "Checked: $SERVICE_FILE_STAGING, $WRAPPER_SCRIPT_STAGING, $SERVICE_FILE_CURRENT, $WRAPPER_SCRIPT_CURRENT"
  exit 1
fi

SERVICE_FILE="$SOURCE_ROOT/.platform/files/sidekiq.service"
WRAPPER_SCRIPT="$SOURCE_ROOT/.platform/files/start-sidekiq.sh"

echo "Resolved Sidekiq service source: $SERVICE_FILE"
echo "Resolved Sidekiq wrapper source: $WRAPPER_SCRIPT"

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
