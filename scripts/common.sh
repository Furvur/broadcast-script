display_logo() {
  echo -e "\e[90m  ____                      _               _   \e[0m"
  echo -e "\e[90m | __ ) _ __ ___   __ _  __| | ___ __ _ ___| |_ \e[0m"
  echo -e "\e[90m |  _ \| '__/ _ \ / _\` |/ _\` |/ __/ _\` / __| __|\e[0m"
  echo -e "\e[90m | |_) | | | (_) | (_| | (_| | (_| (_| \__ \ |_ \e[0m"
  echo -e "\e[90m |____/|_|  \___/ \__,_|\__,_|\___\__,_|___/\__|\e[0m"
  echo -e "\e[90m                                                \e[0m"
  echo -e "\e[90m (c) Copyright 2024, Furvur, Inc.\e[0m"
  echo -e "\e[90m Go to https://sendbroadcast.net for documentation and support.\e[0m"
  echo
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "\e[31mThis script must be run as root.\e[0m"
    exit 1
  fi
}

check_installation_domain() {
  if [ -f /opt/broadcast/.domain ]; then
    return
  fi

  while true; do
    echo -e "\e[32mPlease enter the domain name for this server (eg. broadcast.example.com): \e[0m"
    read installation_domain
    if [ ! -z "$installation_domain" ]; then
      echo "$installation_domain" > /opt/broadcast/.domain
      break
    else
      echo
      echo -e "\e[31mDomain name cannot be empty. Please try again.\e[0m"
      echo
    fi
  done
}

check_license() {
  if [ ! -f /opt/broadcast/.license ]; then
    ask_license
  fi
}

ask_license() {
  local license_file="/opt/broadcast/.license"
  local domain_file="/opt/broadcast/.domain"
  while true; do
    echo
    echo -e "\e[32mPlease enter your license key: \e[0m"
    read license_key
    if [ -z "$license_key" ]; then
      echo
      echo -e "\e[31mLicense key cannot be empty. Please try again.\e[0m"
      echo
    else
      echo
      echo -e "\e[34mYou entered: $license_key\e[0m"
      echo -e "\e[33mIs this correct? (y/n): \e[0m"
      read confirm
      if [[ $confirm =~ ^[Yy]$ ]]; then
        local domain=$(cat "$domain_file")
        echo
        echo -e "\e[34mConfirm you want to install for the domain [$domain] with license key [$license_key]?\e[0m"
        echo -e "\e[33mProceed with installation? [y/n]\e[0m"
        read install_confirm
        if [[ $install_confirm =~ ^[Yy]$ ]]; then
          echo
          echo "$license_key" > "$license_file"
          if validate_license; then
            echo
            echo -e "\e[33mPlease point your domain to the IP address of this server.\e[0m"
            echo -e "\e[33mThis is crucial for the proper functioning of your Broadcast installation.\e[0m"
            echo -e "\e[33mYou can do this by updating your domain's DNS settings to point to this server's IP address.\e[0m"
            echo
            echo -e "\e[33mIf you need further instructions, please see https://sendbroadcast.net/docs/installation\e[0m"
            echo
            echo -e "\e[1;31m** DO THIS BEFORE PROCEEDING **\e[0m"
            echo
            echo -e "\e[93mOnce you've completed this step, press enter to continue...\e[0m"
            read
            break
          else
            rm -f "$license_file"
          fi
        else
          rm -f "$domain_file"
          rm -f "$license_file"
          echo -e "\e[31mInstallation cancelled. Let's start over.\e[0m"
        fi
      else
        echo -e "\e[33mLet's try again.\e[0m"
      fi
    fi
  done
}

validate_license() {
  local license_file="/opt/broadcast/.license"
  local domain_file="/opt/broadcast/.domain"
  local response
  local http_code

  # Check if jq is installed
  if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Installing..."
    sudo apt-get update && sudo apt-get install -y jq
  fi

  if [ ! -f "$license_file" ]; then
    echo "License file not found."
    return 1
  fi

  local license_key=$(cat "$license_file")
  local domain=$(cat "$domain_file")

  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "{\"key\":\"$license_key\", \"domain\":\"$domain\"}" https://sendbroadcast.net/license/check)

  if [ "$http_code" = "401" ]; then
    echo -e "\e[31mInvalid license key. Aborted.\e[0m"
    return 1
  fi

  response=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"key\":\"$license_key\", \"domain\":\"$domain\"}" https://sendbroadcast.net/license/check)

  # Parse the JSON response
  local registry_url=$(echo "$response" | jq -r '.registry_url')

  if [ "$registry_url" != "null" ]; then
    echo -e "\e[32mLicense key valid!\e[0m"

    local registry_login=$(echo "$response" | jq -r '.registry_login')
    local registry_password=$(echo "$response" | jq -r '.registry_password')

    echo "BROADCAST_REGISTRY_URL=$registry_url" >> /opt/broadcast/.env
    echo "BROADCAST_REGISTRY_LOGIN=$registry_login" >> /opt/broadcast/.env
    echo "BROADCAST_REGISTRY_PASSWORD=$registry_password" >> /opt/broadcast/.env

    return 0
  else
    echo -e "\e[31mUnexpected error during license validation. Aborted.\e[0m"
    return 1
  fi
}

load_registry_info() {
  if [ -f /opt/broadcast/.env ]; then
    export $(grep -v '^#' /opt/broadcast/.env | xargs)
  else
    echo -e "\e[31mEnvironment file not found. Please validate your license first.\e[0m"
    return 1
  fi
}
