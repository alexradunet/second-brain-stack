# Documentation Index

Welcome to the Nazar Second Brain documentation.

## Getting Started

| Document | Description |
|----------|-------------|
| [../README.md](../README.md) | Project overview and quick start |
| [../docker/VPS-GUIDE.md](../docker/VPS-GUIDE.md) | VPS deployment guide |
| [syncthing-setup.md](syncthing-setup.md) | Configure vault sync |
| [openclaw-config.md](openclaw-config.md) | Configure AI gateway |

## Understanding the System

| Document | Description |
|----------|-------------|
| [architecture.md](architecture.md) | System design and data flow |
| [vault-structure.md](vault-structure.md) | PARA method and folder conventions |
| [agent.md](agent.md) | Nazar agent system |

## Administration

| Document | Description |
|----------|-------------|
| [../docker/SECURITY.md](../docker/SECURITY.md) | Security hardening guide |
| [../docker/MIGRATION.md](../docker/MIGRATION.md) | Migration from old setup |
| [troubleshooting.md](troubleshooting.md) | Common issues and fixes |

## Reference

| Document | Description |
|----------|-------------|
| [skills.md](skills.md) | Available agent skills |

## Quick Reference

### Services

```bash
# Start/stop/restart
cd ~/nazar/docker
docker compose {up -d|down|restart}

# Or use CLI
nazar-cli {start|stop|restart}
```

### Access Points

| Service | URL (with SSH tunnel) |
|---------|----------------------|
| OpenClaw Gateway | `http://localhost:18789` |
| Syncthing GUI | `http://localhost:8384` |

**SSH Tunnel:**
```bash
ssh -N -L 18789:localhost:18789 -L 8384:localhost:8384 debian@vps-ip
```

### Important Paths

| Path | Purpose |
|------|---------|
| `~/nazar/vault/` | Obsidian vault |
| `~/nazar/.openclaw/` | OpenClaw configuration |
| `~/nazar/syncthing/config/` | Syncthing data |

### CLI Commands

```bash
# OpenClaw
docker compose exec openclaw openclaw configure
docker compose exec openclaw openclaw devices list
docker compose exec openclaw openclaw devices approve <id>

# Syncthing
docker compose exec syncthing syncthing cli show system
docker compose exec syncthing syncthing cli show connections
docker compose exec syncthing syncthing cli show folders

# Or use nazar-cli
nazar-cli configure
nazar-cli token
nazar-cli syncthing-id
```
