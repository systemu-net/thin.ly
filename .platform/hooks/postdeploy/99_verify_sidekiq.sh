#!/usr/bin/env bash
# Verify Sidekiq is actually RUNNING after a deploy — and FAIL the deploy if it is not.
#
# This script used to only print diagnostics. Every check ended in `|| echo "..."` and the file ended on
# a succeeding `ps`, so it returned 0 no matter what it found. On 2026-07-22 Sidekiq stopped booting
# (the launcher pointed at a Ruby ABI a platform upgrade had removed) and this hook reported SUCCESS for
# every deploy that followed. 141 jobs queued and the usage ledger froze for ~27 hours with nothing
# flagged anywhere.
#
# A check that cannot fail is not a check. This one exits non-zero, which fails the deploy — that is the
# point: a release that leaves the worker dead should not be reported as healthy.

set -uo pipefail

READY_TIMEOUT="${SIDEKIQ_READY_TIMEOUT:-45}"   # seconds to allow for a slow boot

dump_diagnostics() {
  echo "--- systemctl status ---"
  systemctl status sidekiq --no-pager 2>&1 | tail -25 || true
  echo "--- last 40 lines of sidekiq.log ---"
  tail -40 /var/app/current/log/sidekiq.log 2>/dev/null || echo "(no sidekiq.log)"
  echo "--- journalctl -u sidekiq ---"
  journalctl -u sidekiq -n 40 --no-pager 2>&1 | tail -40 || true
}

echo "=== Verifying Sidekiq (up to ${READY_TIMEOUT}s) ==="

# Ask SYSTEMD for the worker pid rather than pattern-matching the process table.
#
# `pgrep -f sidekiq` cannot be used here: THIS SCRIPT is called 99_verify_sidekiq.sh, so its own command
# line contains "sidekiq" and it matches itself. The check would then pass whenever the unit merely
# reported active — including mid-bounce of a crash loop — which is the exact false negative this file
# exists to eliminate. Demonstrated: pgrep -f sidekiq matches `bash .../99_verify_sidekiq.sh`.
#
# MainPID is systemd's own view of the process it started, so there is nothing to mis-match.
worker_alive() {
  local pid
  pid="$(systemctl show sidekiq --property=MainPID --value 2>/dev/null || echo 0)"
  [[ "${pid:-0}" =~ ^[0-9]+$ ]] || return 1
  (( pid > 0 )) || return 1
  kill -0 "$pid" 2>/dev/null
}

# Poll rather than sampling once: the unit legitimately takes a few seconds to come up, and a
# crash-looping unit under Restart=always flickers through "active", so a single check can catch it
# mid-bounce and pass.
deadline=$(( SECONDS + READY_TIMEOUT ))
while (( SECONDS < deadline )); do
  if systemctl is-active --quiet sidekiq && worker_alive; then
    # Confirm it STAYS up, rather than being one bounce of a restart loop.
    sleep 5
    if systemctl is-active --quiet sidekiq && worker_alive; then
      echo "OK: sidekiq is active, MainPID $(systemctl show sidekiq --property=MainPID --value) alive."
      exit 0
    fi
  fi
  sleep 3
done

echo "FATAL: sidekiq is not running ${READY_TIMEOUT}s after deploy — failing the deploy."
echo "Background jobs (usage ledger, wallet counters) would silently queue up behind this."
dump_diagnostics
exit 1
