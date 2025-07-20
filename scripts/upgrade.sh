function upgrade() {
  local target_version="${1:-}"
  local current_version=$(get_current_version)
  
  if [ -n "$target_version" ]; then
    echo -e "\e[33mStopping Broadcast service for version-specific upgrade to $target_version...\e[0m"
  else
    target_version="latest"
    echo -e "\e[33mStopping Broadcast service...\e[0m"
  fi
  systemctl stop broadcast

  echo -e "\e[33mRunning Broadcast update script...\e[0m"
  /opt/broadcast/broadcast.sh update

  # Set docker image for specific version if provided
  if [ -n "$target_version" ]; then
    echo -e "\e[33mSetting Docker image for version $target_version...\e[0m"
    set_docker_image "$target_version"
  else
    echo -e "\e[33mSetting Docker image to latest...\e[0m"
    set_docker_image "latest"
  fi

  # Clean up unused images
  echo -e "\e[33mCleaning up unused Docker images...\e[0m"
  docker image prune -f

  # Upgrade the Broadcast containers
  echo -e "\e[33mLogging into Broadcast registry...\e[0m"
  su - broadcast -c 'cd /opt/broadcast && docker compose pull'

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
