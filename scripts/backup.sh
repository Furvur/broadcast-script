function backup() {
  echo -e "\e[33mStarting backup...\e[0m"
  echo "Not yet implemented"
}

function backup_database() {
  create_database_backup_file
}

function create_database_backup_file() {
  echo -e "\e[33mStarting backup...\e[0m"

  timestamp=$(date +%Y-%m-%d-%H-%M-%S)
  backup_file_name="broadcast-backup-$timestamp"

  # We only backup the primary database. The queue and cache databases are ephemeral and considered unimportant for restoration.
  docker compose exec postgres pg_dump -U broadcast -Fc broadcast_primary_production > /opt/broadcast/db/backups/temp-backup.dump
  mv /opt/broadcast/db/backups/temp-backup.dump /opt/broadcast/db/backups/$backup_file_name.dump
  tar -czvf /opt/broadcast/db/backups/$backup_file_name.tar.gz /opt/broadcast/db/backups/$backup_file_name.dump
  rm /opt/broadcast/db/backups/$backup_file_name.dump
  chown -R broadcast:broadcast /opt/broadcast/db/backups

  # Remove all but the most recent backup file
  cd /opt/broadcast/db/backups && ls -t broadcast-backup-*.tar.gz | tail -n +2 | xargs -r rm --

  echo -e "\e[32mBackup successfully archived with timestamp: $timestamp\e[0m"
}

function install_s3cmd() {
  echo -e "\e[33mInstalling s3cmd...\e[0m"
  echo "Not yet implemented"
  # sudo apt-get install s3cmd
}
