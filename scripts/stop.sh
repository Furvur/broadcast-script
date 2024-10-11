function stop() {
  echo -e "\e[33mStopping Broadcast service...\e[0m"
  systemctl stop broadcast
  echo -e "\e[32mBroadcast service stopped successfully!\e[0m"
}
