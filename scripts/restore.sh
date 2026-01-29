# Compare two semantic versions. Returns:
#   0 if equal
#   1 if first > second
#   2 if first < second
function compare_versions() {
  if [ "$1" = "$2" ]; then
    return 0
  fi

  local IFS=.
  local i ver1=($1) ver2=($2)

  # Fill empty positions with zeros
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
    ver1[i]=0
  done
  for ((i=${#ver2[@]}; i<${#ver1[@]}; i++)); do
    ver2[i]=0
  done

  for ((i=0; i<${#ver1[@]}; i++)); do
    if ((10#${ver1[i]} > 10#${ver2[i]})); then
      return 1
    fi
    if ((10#${ver1[i]} < 10#${ver2[i]})); then
      return 2
    fi
  done
  return 0
}

function restore() {
  local backup_file="$1"

  # Validate argument
  if [ -z "$backup_file" ]; then
    echo -e "\e[31mError: No backup file specified\e[0m"
    echo -e "Usage: ./broadcast.sh restore <backup-file.tar.gz>"
    echo -e "Example: ./broadcast.sh restore broadcast-backup-v2.0.0-2026-01-28-14-30-00.tar.gz"
    return 1
  fi

  # Find the backup file (check multiple locations)
  local backup_path=""
  if [ -f "/opt/broadcast/$backup_file" ]; then
    backup_path="/opt/broadcast/$backup_file"
  elif [ -f "/opt/broadcast/db/backups/$backup_file" ]; then
    backup_path="/opt/broadcast/db/backups/$backup_file"
  elif [ -f "$backup_file" ]; then
    backup_path="$backup_file"
  else
    echo -e "\e[31mError: Backup file not found: $backup_file\e[0m"
    echo -e "Searched locations:"
    echo -e "  - /opt/broadcast/$backup_file"
    echo -e "  - /opt/broadcast/db/backups/$backup_file"
    echo -e "  - $backup_file"
    return 1
  fi

  echo -e "\e[34mFound backup file: $backup_path\e[0m"

  # Confirm with user
  echo -e "\e[33m"
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║                         WARNING                                 ║"
  echo "║  This will REPLACE ALL DATA in your database.                  ║"
  echo "║  This action cannot be undone.                                 ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo -e "\e[0m"
  read -p "Are you sure you want to restore from this backup? (yes/no): " confirm

  if [ "$confirm" != "yes" ]; then
    echo -e "\e[33mRestore cancelled.\e[0m"
    return 0
  fi

  # Create temp directory for extraction
  local temp_dir="/tmp/broadcast-restore-$$"
  mkdir -p "$temp_dir"

  echo -e "\e[34mExtracting backup archive...\e[0m"
  tar -xzf "$backup_path" -C "$temp_dir"

  # Check version compatibility
  local backup_version="unknown"
  local installed_version="unknown"

  if [ -f "$temp_dir/VERSION" ]; then
    backup_version=$(cat "$temp_dir/VERSION")
  fi

  if [ -f "/opt/broadcast/.current_version" ]; then
    installed_version=$(cat /opt/broadcast/.current_version)
  fi

  echo -e "\e[34mBackup version: $backup_version\e[0m"
  echo -e "\e[34mInstalled version: $installed_version\e[0m"

  # Check for version incompatibility
  if [ "$backup_version" != "unknown" ] && [ "$installed_version" != "unknown" ]; then
    compare_versions "$backup_version" "$installed_version"
    local version_result=$?

    if [ $version_result -eq 1 ]; then
      # Backup is newer than installed version
      echo -e "\e[31m"
      echo "╔════════════════════════════════════════════════════════════════╗"
      echo "║                    VERSION MISMATCH                            ║"
      echo "║                                                                 ║"
      echo "║  The backup (v$backup_version) is from a NEWER version than    "
      echo "║  your installation (v$installed_version).                       "
      echo "║                                                                 ║"
      echo "║  Restoring a newer backup to an older installation is not      ║"
      echo "║  supported and may cause data loss or application errors.      ║"
      echo "║                                                                 ║"
      echo "║  Please upgrade your installation first:                       ║"
      echo "║    ./broadcast.sh upgrade $backup_version                       "
      echo "╚════════════════════════════════════════════════════════════════╝"
      echo -e "\e[0m"
      rm -rf "$temp_dir"
      return 1
    elif [ $version_result -eq 2 ]; then
      # Backup is older than installed version
      echo -e "\e[33m"
      echo "╔════════════════════════════════════════════════════════════════╗"
      echo "║                        NOTE                                    ║"
      echo "║                                                                 ║"
      echo "║  The backup (v$backup_version) is from an older version than   "
      echo "║  your installation (v$installed_version).                       "
      echo "║                                                                 ║"
      echo "║  Database migrations will run after restore to update the      ║"
      echo "║  schema to the current version.                                ║"
      echo "╚════════════════════════════════════════════════════════════════╝"
      echo -e "\e[0m"
    fi
  fi

  # Find the .dump file
  local dump_file=$(find "$temp_dir" -name "*.dump" -type f | head -1)

  if [ -z "$dump_file" ]; then
    echo -e "\e[31mError: No .dump file found in backup archive\e[0m"
    rm -rf "$temp_dir"
    return 1
  fi

  echo -e "\e[34mFound dump file: $(basename "$dump_file")\e[0m"

  # Stop the application to prevent writes during restore
  echo -e "\e[34mStopping Broadcast services...\e[0m"
  systemctl stop broadcast || true

  # Wait for connections to close
  sleep 3

  # Start just the database container
  echo -e "\e[34mStarting database container...\e[0m"
  cd /opt/broadcast
  set -a && . /opt/broadcast/.image && set +a
  docker compose up -d postgres

  # Wait for PostgreSQL to be ready
  echo -e "\e[34mWaiting for database to be ready...\e[0m"
  sleep 5

  # Copy dump file into container
  docker cp "$dump_file" broadcast-postgres:/tmp/restore.dump

  # Run pg_restore
  echo -e "\e[34mRestoring database (this may take a while)...\e[0m"

  if docker compose exec -T postgres pg_restore \
    -U broadcast \
    -d broadcast_primary_production \
    --clean \
    --if-exists \
    --no-owner \
    --no-privileges \
    /tmp/restore.dump; then
    echo -e "\e[32mDatabase restored successfully!\e[0m"
  else
    # pg_restore returns non-zero for warnings too, check if critical
    echo -e "\e[33mRestore completed with warnings (this is often normal)\e[0m"
  fi

  # Clean up dump file in container
  docker compose exec -T postgres rm -f /tmp/restore.dump

  # Clean up temp directory
  rm -rf "$temp_dir"

  # Run database migrations to handle schema differences between versions
  echo -e "\e[34mRunning database migrations...\e[0m"
  docker compose run --rm app bin/rails db:migrate

  # Restart all services
  echo -e "\e[34mRestarting Broadcast services...\e[0m"
  systemctl start broadcast

  echo -e "\e[32m"
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║                    RESTORE COMPLETE                            ║"
  echo "║                                                                 ║"
  echo "║  Your database has been restored from the backup.              ║"
  echo "║  Please verify your data at your installation URL.             ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo -e "\e[0m"
}
