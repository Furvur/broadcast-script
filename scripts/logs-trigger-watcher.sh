#!/bin/bash
# Event-driven log streaming trigger watcher
# Uses inotifywait to detect when Rails creates/deletes the trigger file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/logs.sh"

TRIGGER_DIR="/opt/broadcast/app/triggers"

# Ensure trigger directory exists
mkdir -p "$TRIGGER_DIR"

echo "[$(date)] Starting log trigger watcher on $TRIGGER_DIR"

# Check if trigger file already exists (in case service restarted while streaming was active)
if [ -f "${TRIGGER_DIR}/logs-stream.txt" ]; then
  if ! is_streaming_active; then
    echo "[$(date)] Trigger file exists, starting log streaming"
    start_log_streaming
  fi
fi

# Watch for file create/delete events
inotifywait -m -e create,delete "$TRIGGER_DIR" 2>/dev/null | while read dir action file; do
  if [[ "$file" == "logs-stream.txt" ]]; then
    if [[ "$action" == "CREATE" ]]; then
      echo "[$(date)] Trigger detected, starting log streaming"
      start_log_streaming
    elif [[ "$action" == "DELETE" ]]; then
      echo "[$(date)] Trigger removed, stopping log streaming"
      stop_log_streaming
    fi
  fi
done
