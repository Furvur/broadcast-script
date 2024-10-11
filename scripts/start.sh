function start() {
  echo -e "\e[33mStarting Broadcast service...\e[0m"
  systemctl start broadcast
  echo -e "\e[32mBroadcast service started successfully!\e[0m"
}
