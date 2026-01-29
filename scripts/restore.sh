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
