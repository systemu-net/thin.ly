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

# Poll rather than sampling once: the unit legitimately takes a few seconds to come up, and — more
# importantly — a crash-looping unit under Restart=always flickers through "active", so a single
# is-active check can catch it mid-bounce and pass. Require the unit active AND a live worker process.
deadline=$(( SECONDS + READY_TIMEOUT ))
while (( SECONDS < deadline )); do
  if systemctl is-active --quiet sidekiq && pgrep -f "sidekiq" >/dev/null 2>&1; then
    # Confirm it stays up, rather than being one bounce of a restart loop.
    sleep 5
    if systemctl is-active --quiet sidekiq && pgrep -f "sidekiq" >/dev/null 2>&1; then
      echo "OK: sidekiq is active with a live worker process."
      exit 0
    fi
  fi
  sleep 3
done

echo "FATAL: sidekiq is not running ${READY_TIMEOUT}s after deploy — failing the deploy."
echo "Background jobs (usage ledger, wallet counters) would silently queue up behind this."
dump_diagnostics
exit 1
