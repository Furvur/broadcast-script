function backup() {
  echo -e "\e[33mStarting backup...\e[0m"

  timestamp=$(date +%Y-%m-%d-%H-%M-%S)

  # We only backup the primary database. The queue and cache databases are ephemeral and considered unimportant for restoration.
  docker compose exec postgres pg_dump -U broadcast -Fc broadcast_primary_production > /opt/broadcast/db/backups/temp-backup.dump
  mv /opt/broadcast/db/backups/temp-backup.dump /opt/broadcast/db/backups/backup-$timestamp.dump
  tar -czvf /opt/broadcast/db/backups/backup-$timestamp.tar.gz /opt/broadcast/db/backups/backup-$timestamp.dump
  rm /opt/broadcast/db/backups/backup-$timestamp.dump
  chown -R broadcast:broadcast /opt/broadcast/db/backups

  echo -e "\e[32mBackup successfully archived with timestamp: $timestamp\e[0m"
}
