function upgrade() {
  echo -e "\e[33mStopping Broadcast service...\e[0m"
  systemctl stop broadcast

  echo -e "\e[33mRunning Broadcast update script...\e[0m"
  /opt/broadcast/broadcast.sh update

  # Clean up unused images
  echo -e "\e[33mCleaning up unused Docker images...\e[0m"
  docker image prune -f

  # Upgrade the Broadcast containers
  echo -e "\e[33mLogging into Broadcast registry...\e[0m"
  su - broadcast -c 'cd /opt/broadcast && docker compose pull'

  echo -e "\e[33mRestarting Broadcast service...\e[0m"
  systemctl start broadcast

  echo -e "\e[32mBroadcast upgrade completed successfully!\e[0m"
}
