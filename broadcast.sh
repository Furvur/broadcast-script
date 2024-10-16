#!/bin/bash

# Broadcast System Installation and Management Script
#
# This script provides functionality to install, upgrade, reboot, backup, and restore
# Broadcast, the email automation software.

# Usage: ./broadcast.sh {install|upgrade|reboot|backup|restore}

set -e
set -u

function getCurrentDir() {
  local current_dir="${BASH_SOURCE%/*}"
  if [[ ! -d "${current_dir}" ]]; then current_dir="$PWD"; fi
  echo "${current_dir}"
}

function includeDependencies() {
  source "${current_dir}/scripts/common.sh"
  source "${current_dir}/scripts/install.sh"
  source "${current_dir}/scripts/start.sh"
  source "${current_dir}/scripts/stop.sh"
  source "${current_dir}/scripts/restart.sh"
  source "${current_dir}/scripts/backup.sh"
  source "${current_dir}/scripts/restore.sh"
  source "${current_dir}/scripts/upgrade.sh"
  source "${current_dir}/scripts/monitor.sh"
  source "${current_dir}/scripts/trigger.sh"
  source "${current_dir}/scripts/update.sh"
}

function display_help() {
  echo "Usage: $0 {install|update|upgrade|restart|stop|start|backup|restore|help|monitor|trigger}"
  echo
  echo "Commands:"
  echo "  install   Install Broadcast onto a fresh Ubuntu server"
  echo "  update    Update Broadcast scripts"
  echo "  upgrade   Upgrade Broadcast images and restart the system"
  echo "  restart   Reboot Broadcast services"
  echo "  stop      Stop Broadcast services"
  echo "  start     Start Broadcast services"
  echo "  backup    Backup Broadcast primary database"
  echo "  restore   Restore Broadcast primary database"
  echo "  help      Display this help message"
  echo "  monitor   Automated feedback of host metrics to the dashboard"
  echo "  trigger   Automated check on triggers from Broadcast to the host"
}

function set_safe_directory() {
  echo "Setting /opt/broadcast as a safe directory for Git..."
  git config --global --add safe.directory /opt/broadcast
  echo "Safe directory set successfully."
}

function check_and_set_safe_directory() {
  if ! git config --global --get safe.directory | grep -q "/opt/broadcast"; then
    set_safe_directory
  fi
}

main() {
  current_dir=$(getCurrentDir)
  includeDependencies

  display_logo
  check_root
  check_installation_domain
  check_license

  # Check and set safe directory before processing any command
  check_and_set_safe_directory

  if [ $# -eq 0 ]; then
    echo "Error: No argument provided"
    display_help
    exit
  fi

  case "$1" in
    install)
      install
      ;;
    upgrade)
      upgrade
      ;;
    restart)
      restart
      ;;
    stop)
      stop
      ;;
    start)
      start
      ;;
    backup)
      backup
      ;;
    restore)
      restore
      ;;
    monitor)
      monitor
      ;;
    trigger)
      trigger
      ;;
    help)
      display_help
      ;;
    *)
      echo "Usage: $0 {install|upgrade|restart|stop|start|backup|restore|help}"
      exit 1
      ;;
  esac
}

# Call main function with all arguments
main "$@"
