#!/usr/bin/env bash
set -e

echo "=== Stopping Sidekiq via systemd ==="

if systemctl is-active --quiet sidekiq; then
  echo "Stopping Sidekiq service..."
  systemctl stop sidekiq || true
  echo "✓ Sidekiq stopped"
else
  echo "Sidekiq service is not running"
fi
