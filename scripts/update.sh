function update() {
  echo -e "\e[33mUpgrading Broadcast scripts...\e[0m"
  # Upgrade the Broadcast scripts
  cd /opt/broadcast

  local current_url
  current_url=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "$current_url" == *"Furvur/broadcast-script"* ]] || [[ "$current_url" == *"furvur/broadcast-script"* ]]; then
    echo -e "\e[33mMigrating remote origin to send-broadcast namespace...\e[0m"
    git remote set-url origin https://github.com/send-broadcast/broadcast-script.git
  fi

  git pull

  echo -e "\e[32mBroadcast scripts upgraded successfully!\e[0m"
}
