#!/usr/bin/env bash

set -euo pipefail

COMPOSE_FILE="/opt/vaultwarden/compose.yaml"

echo "=========================================="
echo " Vaultwarden - Disable Signups"
echo "=========================================="
echo

if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "ERROR: $COMPOSE_FILE not found."
    exit 1
fi

echo "Disabling new Vaultwarden registrations..."

sudo sed -i 's/SIGNUPS_ALLOWED: "true"/SIGNUPS_ALLOWED: "false"/' "$COMPOSE_FILE"

echo
echo "Current signup setting:"
grep "SIGNUPS_ALLOWED" "$COMPOSE_FILE"

echo
echo "Restarting Vaultwarden..."

cd /opt/vaultwarden
sudo docker compose up -d

echo
echo "Waiting for Vaultwarden to restart..."
sleep 5

echo
echo "Vaultwarden status:"
sudo docker ps --filter "name=vaultwarden"

echo
echo "=========================================="
echo " Signups are now DISABLED"
echo "=========================================="