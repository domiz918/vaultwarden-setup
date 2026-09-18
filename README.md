# Vaultwarden + zrok Setup

Simple scripts to install **Vaultwarden** with Docker and expose it through **zrok**, plus a helper script to disable new Vaultwarden sign-ups after your account has been created.

## Files

- `install.sh` — installs Docker, Vaultwarden, zrok, configures the zrok agent, and creates the public zrok share.
- `stop-signups.sh` — disables new Vaultwarden account registration and recreates the Vaultwarden container with the updated setting.

## Requirements

- Ubuntu 24.04 (AARCH64 or ARM64)
- A server with `sudo` access
- A zrok account/access token

## Installation

Run the installer with this command:

```bash
curl -fsSL https://raw.githubusercontent.com/domiz918/vaultwarden-setup/main/install.sh | bash
```

The installer will ask for:

1. Your zrok access token
2. Your personal Vaultwarden hostname/name

The zrok access token is entered without displaying it on screen.

> **Security note:** The zrok token is stored by zrok in the user's zrok configuration after `zrok enable` succeeds. The installer does not put the token into this GitHub repository.

## Create Your Vaultwarden Account

After installation finishes, open the zrok URL printed by the installer and create your Vaultwarden account.

Once your account has been created, you can disable public registration with this command (not necessary though recommended):

```bash
curl -fsSL https://raw.githubusercontent.com/domiz918/vaultwarden-setup/main/stop-signups.sh | bash
```

The script changes:

```yaml
SIGNUPS_ALLOWED: "true"
```

to:

```yaml
SIGNUPS_ALLOWED: "false"
```

and then runs Docker Compose so Vaultwarden uses the new setting.

## Local Vaultwarden Address

Vaultwarden is bound to:

```text
127.0.0.1:8000
```

It is not directly exposed on the server's public network interface. zrok provides the public HTTPS access.

## Useful Commands

Check Vaultwarden:

```bash
cd /opt/vaultwarden
sudo docker compose ps
```

View Vaultwarden logs:

```bash
sudo docker logs -f vaultwarden
```

Check zrok:

```bash
zrok2 agent status
zrok2 list shares
```

Check the zrok systemd service:

```bash
sudo systemctl status zrok2-agent --no-pager
```

Restart the zrok agent:

```bash
sudo systemctl restart zrok2-agent
```

Delete Unnecesary or ghost shares:

- replace **SHARE-TOKEN** with your actual share token you want to delete

```bash
zrok2 list shares
zrok2 delete share SHARE-TOKEN
```

## Important Security Notes

- Once your Vaultwarden account has been created, disable public sign-ups.
- Keep Ubuntu, Docker, Vaultwarden, and zrok updated.

## Repository Structure

```text
vaultwarden-setup/
├── README.md
├── install.sh
└── stop-signups.sh
```

## License

Use and modify these scripts at your own risk.
