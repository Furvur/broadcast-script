function upgrade() {
  echo -e "\e[33mStopping Broadcast service...\e[0m"
  systemctl stop broadcast

  echo -e "\e[33mRunning Broadcast update script...\e[0m"
  sudo -u broadcast /opt/broadcast/broadcast.sh update

  # Upgrade the Broadcast containers
  echo -e "\e[33mLogging into Broadcast registry...\e[0m"
  sudo -u broadcast docker compose pull

  echo -e "\e[33mRestarting Broadcast service...\e[0m"
  systemctl start broadcast

  echo -e "\e[32mBroadcast upgrade completed successfully!\e[0m"
}
