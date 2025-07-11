# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Core Commands

The main entry point is `./broadcast.sh` which must be run as root. Available commands:

```bash
./broadcast.sh install          # Install Broadcast onto a fresh Ubuntu server
./broadcast.sh update           # Update Broadcast scripts
./broadcast.sh upgrade          # Upgrade Broadcast images and restart the system
./broadcast.sh start            # Start Broadcast services
./broadcast.sh stop             # Stop Broadcast services
./broadcast.sh restart          # Restart Broadcast services
./broadcast.sh backup           # Backup Broadcast database and files to S3
./broadcast.sh backup_database  # Backup Broadcast primary database
./broadcast.sh restore          # Restore Broadcast primary database
./broadcast.sh monitor          # Automated feedback of host metrics to the dashboard
./broadcast.sh trigger          # Automated check on triggers from Broadcast to the host
./broadcast.sh validate_license # Validate the license for Broadcast
./broadcast.sh logs <app|job|db> # View logs for specific services
```

## Architecture

This is a Docker-based email automation system with the following components:

### Core Services (docker-compose.yml)
- **app**: Main Rails application container (port 80/443)
- **job**: Background job processor (same image as app, runs `bin/jobs`)
- **postgres**: PostgreSQL 17 database with health checks

### Key Directories
- `/opt/broadcast/app/`: Rails application data (storage, uploads, triggers, monitor)
- `/opt/broadcast/db/`: Database data and backups
- `/opt/broadcast/ssl/`: SSL certificates
- `/opt/broadcast/scripts/`: Management scripts sourced by main broadcast.sh

### Script Architecture
The main `broadcast.sh` script sources modular scripts from `/scripts/`:
- `common.sh`: Shared functions, licensing, validation
- `install.sh`: Fresh installation process
- `start.sh`, `stop.sh`, `restart.sh`: Service management
- `backup.sh`, `restore.sh`: Database operations
- `upgrade.sh`, `update.sh`: System updates
- `monitor.sh`, `trigger.sh`: Automated monitoring
- `logs.sh`: Log management

### Platform Detection
The system automatically detects ARM64/AMD64 architecture and sets appropriate Docker images:
- ARM64: `gitea.hostedapp.org/broadcast/broadcast-arm:latest`
- AMD64: `gitea.hostedapp.org/broadcast/broadcast:latest`

### Configuration Files
- `.domain`: Installation domain (created during install)
- `.license`: License key (validated against sendbroadcast.net)
- `.env`: Registry credentials (populated after license validation)
- `app/.env`: Rails application environment
- `db/.env`: PostgreSQL environment

### Web Server
Uses Caddy as reverse proxy with:
- Automatic HTTPS with internal TLS
- WebSocket support for Rails
- Security headers and GZIP compression
- Proxies to Rails app on port 3000

## Development Notes

- System requires Ubuntu Server 24.04 with minimum 2GB RAM and 40GB disk
- All operations must be run as root
- Git safe directory is automatically configured for `/opt/broadcast`
- Database includes automated health checks and initialization scripts
- Log rotation configured (10MB max, 3 files)

## Development style
- Always remember to add a newline to any files you create
