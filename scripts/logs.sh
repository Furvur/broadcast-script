function display_logs() {
  if [ $# -eq 2 ] && [ "$1" = "logs" ]; then
    case "$2" in
      app)
        docker logs --follow app
        ;;
      job)
        docker logs --follow job
        ;;
      db)
        docker logs --follow postgres
        ;;
      *)
        echo "Please specify a valid log type: app, job, or db"
        exit 1
        ;;
    esac
  else
    echo "Usage: $0 logs <app|job|db>"
    exit 1
  fi
}

# === On-Demand Log Streaming (for web UI) ===
LOGS_TRIGGER="/opt/broadcast/app/triggers/logs-stream.txt"
LOGS_OUTPUT="/opt/broadcast/logs/application.log"
LOGS_PID_FILE="/opt/broadcast/logs/.streaming.pid"

is_streaming_active() {
  if [ -f "$LOGS_PID_FILE" ]; then
    local pid=$(cat "$LOGS_PID_FILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      # Process exists - verify it's still our streaming process
      if ps -p "$pid" -o args= 2>/dev/null | grep -q "docker logs"; then
        return 0
      fi
    fi
    # Stale PID file - clean up
    rm -f "$LOGS_PID_FILE"
  fi
  return 1
}

start_log_streaming() {
  echo "[$(date)] Starting log streaming..."
  mkdir -p "$(dirname "$LOGS_OUTPUT")"

  # Start in new process group so we can kill the whole tree
  setsid bash -c '
    docker logs -f --tail=100 --timestamps app 2>&1 | sed "s/^/[web] /" &
    docker logs -f --tail=100 --timestamps job 2>&1 | sed "s/^/[job] /" &
    wait
  ' > "$LOGS_OUTPUT" 2>&1 &

  local pid=$!
  echo "$pid" > "$LOGS_PID_FILE"
  echo "[$(date)] Log streaming started (PID: $pid)"
}

stop_log_streaming() {
  if [ -f "$LOGS_PID_FILE" ]; then
    local pid=$(cat "$LOGS_PID_FILE" 2>/dev/null)
    echo "[$(date)] Stopping log streaming (PID: $pid)..."

    if [ -n "$pid" ]; then
      # Kill entire process group
      pkill -TERM -P "$pid" 2>/dev/null
      kill -TERM "$pid" 2>/dev/null

      # Wait briefly, then force kill if needed
      sleep 1
      pkill -KILL -P "$pid" 2>/dev/null
      kill -KILL "$pid" 2>/dev/null
    fi

    rm -f "$LOGS_PID_FILE"
    rm -f "$LOGS_OUTPUT"
    echo "[$(date)] Log streaming stopped"
  fi
}

check_log_streaming_trigger() {
  # Safety check: only run if volume mount exists (container was recreated with new compose)
  if ! docker exec app test -d /rails/logs 2>/dev/null; then
    # Volume not mounted yet - clean up any stale trigger
    if [ -f "$LOGS_TRIGGER" ]; then
      rm -f "$LOGS_TRIGGER"
      echo "[$(date)] Removed stale logs-stream.txt trigger (volume not mounted)"
    fi
    return
  fi

  if [ -f "$LOGS_TRIGGER" ]; then
    if ! is_streaming_active; then
      start_log_streaming
    fi
  else
    if is_streaming_active; then
      stop_log_streaming
    fi
  fi
}
