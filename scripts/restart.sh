function restart() {
  echo -e "\e[33mRestarting Broadcast service...\e[0m"
  systemctl stop broadcast
  systemctl start broadcast
  echo -e "\e[32mBroadcast service restarted successfully!\e[0m"
}
