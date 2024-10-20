function upgrade() {
  echo -e "\e[33mStopping Broadcast service...\e[0m"
  systemctl stop broadcast

  echo -e "\e[33mUpgrading Broadcast scripts...\e[0m"
  # Upgrade the Broadcast scripts
  cd /opt/broadcast
  git pull

  # Change ownership of the Broadcast directory to the broadcast user
  sudo chown -R broadcast:broadcast /opt/broadcast

  # Upgrade the Broadcast containers
  echo -e "\e[33mLogging into Broadcast registry...\e[0m"
  sudo -u broadcast docker compose pull

  echo -e "\e[33mRestarting Broadcast service...\e[0m"
  systemctl start broadcast

  echo -e "\e[32mBroadcast upgrade completed successfully!\e[0m"
}
