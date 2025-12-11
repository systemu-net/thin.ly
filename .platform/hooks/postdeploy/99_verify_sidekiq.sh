#!/usr/bin/env bash
# Test script to verify Sidekiq systemd setup

echo "=== Sidekiq Systemd Status ==="
systemctl status sidekiq --no-pager || echo "Service not found"

echo ""
echo "=== Recent Sidekiq Logs ==="
journalctl -u sidekiq -n 20 --no-pager || echo "No logs found"

echo ""
echo "=== Sidekiq Process ==="
ps aux | grep sidekiq | grep -v grep || echo "No process found"
