# Nazar Deploy

Docker deployment stack for the Nazar AI assistant (OpenClaw + Syncthing).

## Architecture

Two containers, one shared vault:

- **nazar-gateway** — OpenClaw with voice tools (Whisper STT + Piper TTS)
- **nazar-syncthing** — Syncthing for vault sync across devices

Both bind-mount the same vault directory. The gateway uses `network_mode: host` with integrated Tailscale Serve (automatic HTTPS proxy). Syncthing UI is bound to 127.0.0.1 (access via manual `tailscale serve`).

## Quick Start

```bash
# On your VPS
git clone <this-repo> /srv/nazar/deploy
cd /srv/nazar/deploy
sudo bash scripts/setup-vps.sh

# Edit secrets
nano /srv/nazar/.env

# Restart with secrets
cd /srv/nazar && docker compose restart
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Two-service stack definition |
| `Dockerfile.nazar` | OpenClaw + voice tools image |
| `openclaw.json` | Agent config (multi-model, sandbox) |
| `.env.example` | Secrets template |
| `scripts/setup-vps.sh` | VPS bootstrap script |

## Ports

| Port | Service | Access |
|------|---------|--------|
| 443 (HTTPS) | OpenClaw Gateway | `https://<tailscale-hostname>/` (automatic via integrated Tailscale Serve) |
| 8384 | Syncthing UI | `http://<tailscale-ip>:8384` (manual `tailscale serve`) |
| 22000 | Syncthing sync | Public |
| 21027 | Syncthing discovery | Public |

## Management

```bash
cd /srv/nazar
docker compose ps          # Status
docker compose logs -f     # Logs
docker compose restart     # Restart
docker compose down        # Stop
docker compose build       # Rebuild
```
