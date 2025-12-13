#!/usr/bin/env bash
# Test script to verify Sidekiq systemd setup

echo "=== Sidekiq Systemd Status ==="
systemctl status sidekiq --no-pager || echo "Service not found"

echo ""
echo "=== Recent Sidekiq Logs (journalctl) ==="
journalctl -u sidekiq -n 30 --no-pager || echo "No logs found"

echo ""
echo "=== Sidekiq Application Log ==="
if [ -f /var/app/current/log/sidekiq.log ]; then
  echo "Last 30 lines of sidekiq.log:"
  tail -30 /var/app/current/log/sidekiq.log
else
  echo "No sidekiq.log found"
fi

echo ""
echo "=== Sidekiq Processes ==="
ps auxf | grep -E "(sidekiq|PID)" | grep -v grep || echo "No process found"
