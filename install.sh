#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Vaultwarden + Docker + zrok ARM64 automated setup
# ============================================================

# -----------------------------
# User configuration
# -----------------------------

echo
echo "=========================================="
echo " Vaultwarden + zrok Setup"
echo "=========================================="
echo

read -r -s -p "Enter your zrok access token: " ACC_TOKEN
echo

read -r -p "Enter your Vaultwarden vault name: " VAULT_NAME
echo

if [[ -z "$ACC_TOKEN" ]]; then
    echo "ERROR: zrok access token cannot be empty."
    exit 1
fi

if [[ -z "$VAULT_NAME" ]]; then
    echo "ERROR: VAULT_NAME cannot be empty."
    exit 1
fi

# Only allow a simple hostname/name format.
# This prevents accidentally putting spaces or shell characters
# into the zrok share name.
if [[ ! "$VAULT_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
    echo "ERROR: VAULT_NAME contains invalid characters."
    echo "Use only letters, numbers, dots, underscores and hyphens."
    exit 1
fi

CURRENT_USER="${SUDO_USER:-$USER}"
USER_HOME="$(getent passwd "$CURRENT_USER" | cut -d: -f6)"

if [[ -z "$USER_HOME" ]]; then
    echo "ERROR: Could not determine home directory for $CURRENT_USER."
    exit 1
fi

echo
echo "Configuration:"
echo "  Linux user : $CURRENT_USER"
echo "  Home       : $USER_HOME"
echo "  Vault name : $VAULT_NAME"
echo

sleep 3


# ============================================================
# 1. Update Ubuntu
# ============================================================

echo
echo "=========================================="
echo "1/8 Updating Ubuntu"
echo "=========================================="

sudo apt update

echo
echo "Waiting briefly before upgrade..."
sleep 3

sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y

echo
echo "Ubuntu update complete."
sleep 3


# ============================================================
# 2. Install Docker
# ============================================================

echo
echo "=========================================="
echo "2/8 Installing Docker"
echo "=========================================="

sudo apt install -y docker.io docker-compose-v2

echo
echo "Enabling Docker..."
sudo systemctl enable --now docker

echo
echo "Waiting for Docker to become ready..."

for i in {1..30}; do
    if sudo systemctl is-active --quiet docker && sudo docker info >/dev/null 2>&1; then
        echo "Docker is ready."
        break
    fi

    if [[ "$i" -eq 30 ]]; then
        echo "ERROR: Docker did not become ready."
        exit 1
    fi

    sleep 2
done

sleep 3


# ============================================================
# 3. Create Vaultwarden directories
# ============================================================

echo
echo "=========================================="
echo "3/8 Creating Vaultwarden directories"
echo "=========================================="

sudo mkdir -p /opt/vaultwarden/data

sudo chown -R "$CURRENT_USER:$CURRENT_USER" /opt/vaultwarden

echo
echo "Vaultwarden directory:"
ls -ld /opt/vaultwarden
ls -ld /opt/vaultwarden/data

sleep 3


# ============================================================
# 4. Create Docker Compose file
# ============================================================

echo
echo "=========================================="
echo "4/8 Creating Vaultwarden Docker config"
echo "=========================================="

sudo tee /opt/vaultwarden/compose.yaml > /dev/null <<'EOF'
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped

    environment:
      SIGNUPS_ALLOWED: "true"

    volumes:
      - ./data:/data

    ports:
      - "127.0.0.1:8000:80"
EOF

sudo chown "$CURRENT_USER:$CURRENT_USER" /opt/vaultwarden/compose.yaml

echo
echo "Created:"
cat /opt/vaultwarden/compose.yaml

sleep 3


# ============================================================
# 5. Start Vaultwarden
# ============================================================

echo
echo "=========================================="
echo "5/8 Starting Vaultwarden"
echo "=========================================="

cd /opt/vaultwarden

sudo docker compose pull

echo
echo "Waiting briefly after image download..."
sleep 3

sudo docker compose up -d

echo
echo "Waiting for Vaultwarden container..."
sleep 5

sudo docker ps --filter "name=vaultwarden"

echo
echo "Checking Vaultwarden..."
if sudo docker ps --filter "name=vaultwarden" --filter "status=running" | grep -q vaultwarden; then
    echo "Vaultwarden container is running."
else
    echo "ERROR: Vaultwarden container does not appear to be running."
    sudo docker logs vaultwarden --tail 50 || true
    exit 1
fi

sleep 3


# ============================================================
# 6. Install latest zrok ARM64
# ============================================================

echo
echo "=========================================="
echo "6/8 Installing latest zrok Linux ARM64"
echo "=========================================="

cd /tmp

echo "Checking CPU architecture..."

ARCH="$(uname -m)"

if [[ "$ARCH" != "aarch64" ]]; then
    echo
    echo "WARNING:"
    echo "This script is configured for Linux ARM64."
    echo "Detected architecture: $ARCH"
    echo
    echo "For an Oracle ARM Ampere instance this should normally be:"
    echo "aarch64"
    echo
    exit 1
fi

echo "Architecture: $ARCH"

echo
echo "Finding latest zrok release..."

VERSION="$(
    curl -fsSL \
        https://api.github.com/repos/openziti/zrok/releases/latest |
        sed -n 's/.*"tag_name": "\(.*\)",/\1/p' |
        head -n 1
)"

if [[ -z "$VERSION" ]]; then
    echo "ERROR: Could not determine latest zrok version."
    exit 1
fi

ZROK_VERSION="${VERSION#v}"
ZROK_FILE="zrok_${ZROK_VERSION}_linux_arm64.tar.gz"
ZROK_URL="https://github.com/openziti/zrok/releases/download/${VERSION}/${ZROK_FILE}"

echo
echo "Latest zrok version: $VERSION"
echo "Downloading:"
echo "$ZROK_FILE"
echo

rm -f "$ZROK_FILE"

wget -q --show-progress "$ZROK_URL"

echo
echo "Extracting zrok..."

rm -rf /tmp/zrok-extract
mkdir -p /tmp/zrok-extract

tar -xzf "$ZROK_FILE" -C /tmp/zrok-extract

if [[ ! -f /tmp/zrok-extract/zrok2 ]]; then
    echo "ERROR: zrok2 binary was not found after extraction."
    find /tmp/zrok-extract -maxdepth 2 -type f
    exit 1
fi

sudo install -m 0755 /tmp/zrok-extract/zrok2 /usr/local/bin/zrok2

echo
echo "Installed zrok:"
/usr/local/bin/zrok2 version || true

sleep 3


# ============================================================
# 7. Configure zrok + systemd agent
# ============================================================

echo
echo "=========================================="
echo "7/8 Configuring zrok agent"
echo "=========================================="

echo
echo "Enabling zrok account..."

# Run as the actual SSH user, NOT root.
# zrok stores its configuration under the user's home directory.
sudo -u "$CURRENT_USER" env \
    HOME="$USER_HOME" \
    /usr/local/bin/zrok2 enable "$ACC_TOKEN"

echo
echo "Checking zrok configuration..."

sudo -u "$CURRENT_USER" env \
    HOME="$USER_HOME" \
    /usr/local/bin/zrok2 agent status || true

echo
echo "zrok names:"
sudo -u "$CURRENT_USER" env \
    HOME="$USER_HOME" \
    /usr/local/bin/zrok2 list names || true

echo
echo "zrok shares:"
sudo -u "$CURRENT_USER" env \
    HOME="$USER_HOME" \
    /usr/local/bin/zrok2 list shares || true


# ------------------------------------------
# Create systemd service
# ------------------------------------------

echo
echo "Creating zrok2 systemd service..."

sudo tee /etc/systemd/system/zrok2-agent.service > /dev/null <<EOF
[Unit]
Description=zrok2 agent
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=$CURRENT_USER
Environment=HOME=$USER_HOME
ExecStart=/usr/local/bin/zrok2 agent start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

sudo systemctl enable zrok2-agent

echo
echo "Starting zrok2 agent..."

sudo systemctl start zrok2-agent

echo
echo "Waiting for zrok agent..."
sleep 5

sudo systemctl status zrok2-agent --no-pager

sleep 3


# ============================================================
# 8. Create public Vaultwarden share
# ============================================================

echo
echo "=========================================="
echo "8/8 Creating public zrok share"
echo "=========================================="

SHARE_NAME="public:${VAULT_NAME}-vault"

echo
echo "Share name:"
echo "$SHARE_NAME"

echo
echo "Starting public zrok share..."

sudo -u "$CURRENT_USER" env \
    HOME="$USER_HOME" \
    /usr/local/bin/zrok2 share public \
        http://127.0.0.1:8000 \
        --headless \
        -n "$SHARE_NAME"

echo
echo "Waiting for share..."
sleep 5

echo
echo "Final zrok agent status:"

sudo -u "$CURRENT_USER" env \
    HOME="$USER_HOME" \
    /usr/local/bin/zrok2 agent status


# ============================================================
# Cleanup
# ============================================================

echo
echo "Cleaning temporary zrok files..."

rm -rf /tmp/zrok-extract
rm -f "/tmp/$ZROK_FILE"

# Do not keep the access token in the script's environment.
unset ACC_TOKEN


# ============================================================
# Finished
# ============================================================

echo
echo "=========================================="
echo " SETUP COMPLETE"
echo "=========================================="
echo

echo "Vaultwarden:"
echo "  http://127.0.0.1:8000"

echo
echo "zrok share:"
echo "  $SHARE_NAME"

echo
echo "zrok agent:"
sudo systemctl is-active zrok2-agent

echo
echo "Docker:"
sudo docker ps --filter "name=vaultwarden"

echo
echo "=========================================="
echo " Your Vaultwarden server is ready."
echo "=========================================="
echo