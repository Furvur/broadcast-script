function update() {
  echo -e "\e[33mUpgrading Broadcast scripts...\e[0m"
  # Upgrade the Broadcast scripts
  cd /opt/broadcast
  git pull

  # Update systemd service for broadcast
  source scripts/init-services.sh
  create_broadcast_service

  # Change ownership of the Broadcast directory to the broadcast user
  sudo chown -R broadcast:broadcast /opt/broadcast

  echo -e "\e[32mBroadcast scripts upgraded successfully!\e[0m"
}
