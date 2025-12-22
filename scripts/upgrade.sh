function upgrade() {
  local target_version="${1:-}"

  if [ -n "$target_version" ]; then
    echo -e "\e[33mStopping Broadcast service for version-specific upgrade to $target_version...\e[0m"
  else
    echo -e "\e[33mStopping Broadcast service...\e[0m"
  fi
  systemctl stop broadcast

  echo -e "\e[33mUpdating Broadcast scripts...\e[0m"
  /opt/broadcast/broadcast.sh update

  # Re-exec with updated scripts to ensure new code runs
  echo -e "\e[33mReloading with updated scripts...\e[0m"
  exec /opt/broadcast/broadcast.sh _upgrade_continue "$target_version"
}

function _upgrade_continue() {
  local target_version="${1:-}"
  local current_version=$(get_current_version)

  if [ -z "$target_version" ]; then
    target_version="latest"
  fi

  # Set docker image for target version
  echo -e "\e[33mSetting Docker image for version $target_version...\e[0m"
  set_docker_image "$target_version"

  # Clean up unused images
  echo -e "\e[33mCleaning up unused Docker images...\e[0m"
  docker image prune -f

  # Upgrade the Broadcast containers
  echo -e "\e[33mPulling Broadcast containers for version $target_version...\e[0m"
  su - broadcast -c 'cd /opt/broadcast && set -a && source .image && set +a && docker compose pull'

  echo -e "\e[33mRestarting Broadcast service...\e[0m"
  systemctl start broadcast

  # Log version change to history
  log_version_change "upgrade" "$current_version" "$target_version"

  if [ "$target_version" != "latest" ]; then
    echo -e "\e[32mBroadcast upgrade to version $target_version completed successfully!\e[0m"
  else
    echo -e "\e[32mBroadcast upgrade completed successfully!\e[0m"
  fi
}
