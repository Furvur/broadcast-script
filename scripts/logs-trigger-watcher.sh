#!/bin/bash
# Log streaming trigger watcher
#
# Reconciles desired state (does the logs-stream.txt trigger exist?) with actual
# state (is a streamer running?) via check_log_streaming_trigger. Three things
# drive a reconcile:
#   1. startup        - recover a trigger left over across a service/host restart
#   2. inotify events - instant start/stop when the user clicks Start/Stop
#   3. a periodic tick - self-heal if the streamer dies for any reason (e.g. the
#                        containers were recreated) while the trigger is present
# All three funnel through a single flock-guarded reconcile() so they can never
# race on the PID file or spawn duplicate streamers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/logs.sh"

TRIGGER_DIR="/opt/broadcast/app/triggers"
LOCK_FILE="/opt/broadcast/logs/.logs-watcher.lock"
RECONCILE_INTERVAL=30

# Ensure trigger and lock directories exist
mkdir -p "$TRIGGER_DIR"
mkdir -p "$(dirname "$LOCK_FILE")"

echo "[$(date)] Starting log trigger watcher on $TRIGGER_DIR"

# Serialize all reconciliation so the inotify handler and the periodic tick
# cannot interleave start/stop on the shared PID file.
reconcile() {
  ( flock -w 10 9 || exit 0; check_log_streaming_trigger ) 9>"$LOCK_FILE"
}

# 1. Reconcile once on startup (recovers a trigger that outlived the streamer).
reconcile

# 3. Periodic safety net: catch a streamer that died while the trigger is still
#    present. Runs in the unit's cgroup, so systemd reaps it on stop/restart.
(
  while true; do
    sleep "$RECONCILE_INTERVAL"
    reconcile
  done
) &

# 2. Event-driven path for instant response. We watch modify/close_write in
#    addition to create/delete because Rails rewrites an *existing* trigger file
#    (a modify, not a create) when Start is clicked while a stale trigger lingers
#    - the original create-only watch silently ignored that and never re-armed.
inotifywait -m -e create,modify,close_write,delete,moved_to,moved_from "$TRIGGER_DIR" 2>/dev/null |
  while read -r dir action file; do
    if [[ "$file" == "logs-stream.txt" ]]; then
      echo "[$(date)] Trigger event: $action $file"
      reconcile
    fi
  done
