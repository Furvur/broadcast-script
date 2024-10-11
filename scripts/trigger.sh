function trigger() {
  # Check if the upgrade.txt file exists in the triggers directory
  if [ -f "/opt/broadcast/app/triggers/upgrade.txt" ]; then
    # Remove the upgrade.txt file
    rm "/opt/broadcast/app/triggers/upgrade.txt"
    # If the file exists, run the upgrade command
    /opt/broadcast/broadcast.sh upgrade
  fi

  if [ -f "/opt/broadcast/app/triggers/domains.txt" ]; then
    # Copy domains.txt to /opt/broadcast/.other_domains
    cp "/opt/broadcast/app/triggers/domains.txt" "/opt/broadcast/.other_domains"

    domain=$(cat /opt/broadcast/.domain)
    if [ -f /opt/broadcast/.other_domains ]; then
      other_domains=$(cat /opt/broadcast/.other_domains | tr '\n' ',' | sed 's/,$//')
      echo "TLS_DOMAIN=$domain,$other_domains" >> /opt/broadcast/app/.env
    else
      echo "TLS_DOMAIN=$domain" >> /opt/broadcast/app/.env
    fi

    # Remove the domains.txt file
    rm "/opt/broadcast/app/triggers/domains.txt"

    /opt/broadcast/broadcast.sh restart
  fi
}
