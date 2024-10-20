#!/bin/bash

create_broadcast_service() {
  echo -e "\e[33mCreating systemd service for Broadcast...\e[0m"

  # Disable the service if it exists
  sudo systemctl disable broadcast.service

  # Create systemd service file for Broadcast
  sudo tee /etc/systemd/system/broadcast.service > /dev/null <<EOT
[Unit]
Description=Broadcast
Requires=docker.service
After=docker.service

[Service]
Type=simple
ExecStart=/bin/bash -c "set -a && . /opt/broadcast/.image && set +a && docker compose -f /opt/broadcast/docker-compose.yml up"
ExecStop=/bin/bash -c "set -a && . /opt/broadcast/.image && set +a && docker compose -f /opt/broadcast/docker-compose.yml down"
Restart=always
User=broadcast
WorkingDirectory=/opt/broadcast

[Install]
WantedBy=multi-user.target
EOT

  # Reload systemd to recognize the new service
  sudo systemctl daemon-reload

  # Enable the service to start on boot
  sudo systemctl enable broadcast.service
}
