function downgrade() {
  local target_version="$1"
  
  # Validate that target version is provided
  if [ -z "$target_version" ]; then
    echo -e "\e[31mError: Target version is required for downgrade operation\e[0m"
    echo -e "\e[33mUsage: broadcast.sh downgrade <version>\e[0m"
    return 1
  fi
  
  # Validate semantic version format using helper function
  if ! validate_semantic_version "$target_version"; then
    echo -e "\e[31mError: Invalid version format. Use semantic versioning (e.g., 1.2.3)\e[0m"
    return 1
  fi
  
  # Get current version using helper function
  local current_version=$(get_current_version)
  
  echo -e "\e[33mInitiating downgrade from version $current_version to $target_version...\e[0m"
  echo -e "\e[93mWarning: Downgrade operations should only be performed after ensuring compatibility\e[0m"
  
  # Stop services
  echo -e "\e[33mStopping Broadcast service for downgrade to $target_version...\e[0m"
  systemctl stop broadcast
  
  # Update scripts (same as upgrade)
  echo -e "\e[33mRunning Broadcast update script...\e[0m"
  /opt/broadcast/broadcast.sh update
  
  # Set docker image for target version
  echo -e "\e[33mSetting Docker image for version $target_version...\e[0m"
  set_docker_image "$target_version"
  
  # Clean up unused images
  echo -e "\e[33mCleaning up unused Docker images...\e[0m"
  docker image prune -f
  
  # Pull target version containers
  echo -e "\e[33mPulling Broadcast containers for version $target_version...\e[0m"
  su - broadcast -c 'cd /opt/broadcast && docker compose pull'
  
  # Restart services
  echo -e "\e[33mRestarting Broadcast service...\e[0m"
  systemctl start broadcast
  
  # Log version change to history
  log_version_change "downgrade" "$current_version" "$target_version"
  
  echo -e "\e[32mBroadcast downgrade to version $target_version completed successfully!\e[0m"
  echo -e "\e[33mCurrent version: $target_version (previous: $current_version)\e[0m"
}