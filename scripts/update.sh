function update() {
  echo -e "\e[33mUpgrading Broadcast scripts...\e[0m"
  # Upgrade the Broadcast scripts
  cd /opt/broadcast
  git pull
  echo -e "\e[32mBroadcast scripts upgraded successfully!\e[0m"
}
