#!/bin/bash
#
# Post-upgrade Docker image cleanup
# Waits for all containers to stabilize, then prunes unused images.
# Triggered by: systemctl start broadcast-post-upgrade-cleanup.service

CONTAINERS=("app" "job" "postgres")
STABILITY_SECONDS=60

echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Post-upgrade cleanup started, waiting ${STABILITY_SECONDS}s for containers to stabilize..."
sleep "$STABILITY_SECONDS"

# Check all containers are running and have been up for at least STABILITY_SECONDS
all_stable=true
for container in "${CONTAINERS[@]}"; do
  status=$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null)
  if [ "$status" != "running" ]; then
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Container '$container' is not running (status: ${status:-not found}). Skipping cleanup."
    all_stable=false
    break
  fi

  started_at=$(docker inspect --format '{{.State.StartedAt}}' "$container" 2>/dev/null)
  started_epoch=$(date -d "$started_at" +%s 2>/dev/null)
  now_epoch=$(date +%s)
  uptime_seconds=$((now_epoch - started_epoch))

  if [ "$uptime_seconds" -lt "$STABILITY_SECONDS" ]; then
    echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Container '$container' has only been running for ${uptime_seconds}s (need ${STABILITY_SECONDS}s). Skipping cleanup."
    all_stable=false
    break
  fi
done

if [ "$all_stable" = true ]; then
  echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - All containers stable. Pruning unused Docker images..."
  docker image prune -af
  echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Docker image cleanup completed."
else
  echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') - Cleanup skipped due to unstable containers."
fi
