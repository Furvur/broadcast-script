function trigger() {
  # Check if the upgrade.txt file exists in the triggers directory
  if [ -f "/opt/broadcast/app/triggers/upgrade.txt" ]; then
    # Read the content of the upgrade.txt file
    trigger_content=$(cat "/opt/broadcast/app/triggers/upgrade.txt" 2>/dev/null || echo "")
    
    # Validate if content looks like a version number (semantic versioning: x.y.z)
    if echo "$trigger_content" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9\.-]+)?(\+[a-zA-Z0-9\.-]+)?$'; then
      target_version="$trigger_content"
      echo "[$(date)] upgrade triggered with target version: $target_version"
      
      # Remove the upgrade.txt file
      rm "/opt/broadcast/app/triggers/upgrade.txt"
      
      # Run upgrade with version parameter
      /opt/broadcast/broadcast.sh upgrade "$target_version"
      
      echo "[$(date)] upgrade to version $target_version completed"
    else
      # Fallback to standard upgrade for invalid/empty version content
      echo "[$(date)] upgrade triggered (fallback mode - invalid or empty version content: '$trigger_content')"
      
      # Remove the upgrade.txt file
      rm "/opt/broadcast/app/triggers/upgrade.txt"
      
      # Run standard upgrade without version
      /opt/broadcast/broadcast.sh upgrade
      
      echo "[$(date)] upgrade completed (fallback mode)"
    fi
  fi

  if [ -f "/opt/broadcast/app/triggers/domains.txt" ]; then
    echo "[$(date)] domains change triggered, updating domains"
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

    # Ensure /opt/broadcast and all its contents belong to broadcast:broadcast
    chown -R broadcast:broadcast /opt/broadcast

    echo "[$(date)] domains updated, restarting services"

    /opt/broadcast/broadcast.sh restart
  fi

  if [ -f "/opt/broadcast/app/triggers/backup-db.txt" ]; then
    echo "[$(date)] backup triggered, backing up database"
    rm "/opt/broadcast/app/triggers/backup-db.txt"
    /opt/broadcast/broadcast.sh backup_database
  fi
}
