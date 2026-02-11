#!/bin/bash
#
# Nazar Second Brain - Docker Management CLI
# Single debian user setup
# Helper script for managing OpenClaw + Syncthing containers
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Find compose directory
find_compose_dir() {
    if [ -f "docker-compose.yml" ]; then
        pwd
    elif [ -f "$HOME/nazar/docker/docker-compose.yml" ]; then
        echo "$HOME/nazar/docker"
    elif [ -f "/home/debian/nazar/docker/docker-compose.yml" ]; then
        echo "/home/debian/nazar/docker"
    else
        echo ""
    fi
}

COMPOSE_DIR=$(find_compose_dir)

if [ -z "$COMPOSE_DIR" ]; then
    log_error "Cannot find docker-compose.yml"
    log_info "Please run this script from the docker directory or ~/nazar/docker"
    exit 1
fi

cd "$COMPOSE_DIR"

# Get vault path from .env
get_vault_path() {
    grep "^VAULT_HOST_PATH=" .env 2>/dev/null | cut -d= -f2 || echo "$HOME/nazar/vault"
}

# Get deployment mode
get_deployment_mode() {
    grep "^DEPLOYMENT_MODE=" .env 2>/dev/null | cut -d= -f2 || echo "sshtunnel"
}

# Show help
show_help() {
    cat << 'EOF'
Nazar Second Brain - Docker Management CLI
Single user: debian + Docker containers

USAGE:
    nazar-cli <command> [options]

COMMANDS:
    status              Show service status and resource usage
    logs [service]      Show logs (all or specific service)
    start               Start all services
    stop                Stop all services
    restart             Restart all services
    update              Pull latest images and restart
    shell               Open shell in OpenClaw container
    configure           Run OpenClaw configuration wizard
    token               Show gateway token
    backup              Create backup of vault and configs
    restore <file>      Restore from backup
    syncthing-id        Show Syncthing Device ID
    tunnel              Show SSH tunnel command
    vault               Open vault directory
    clean               Remove unused Docker resources
    help                Show this help message

SERVICES:
    openclaw            OpenClaw gateway
    syncthing           Syncthing sync
    tailscale           Tailscale VPN (if enabled)

EXAMPLES:
    nazar-cli status
    nazar-cli logs openclaw
    nazar-cli restart
    nazar-cli backup
    nazar-cli tunnel    # Show SSH tunnel command

EOF
}

# Show status
show_status() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║              Nazar Second Brain - Status                      ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    
    docker compose ps
    
    echo ""
    log_info "Resource Usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.PIDs}}" 2>/dev/null || echo "Containers not running"
    
    echo ""
    DEPLOYMENT_MODE=$(get_deployment_mode)
    log_info "Deployment Mode: $DEPLOYMENT_MODE"
    
    if [ "$DEPLOYMENT_MODE" = "tailscale" ]; then
        echo ""
        log_info "Tailscale Status:"
        docker compose exec tailscale tailscale status 2>/dev/null || echo "Tailscale not ready"
    fi
}

# Show logs
show_logs() {
    local service=$1
    if [ -n "$service" ]; then
        docker compose logs -f "$service"
    else
        docker compose logs -f
    fi
}

# Start services
start_services() {
    log_info "Starting services..."
    docker compose up -d
    log_success "Services started"
    show_status
}

# Stop services
stop_services() {
    log_info "Stopping services..."
    docker compose down
    log_success "Services stopped"
}

# Restart services
restart_services() {
    log_info "Restarting services..."
    docker compose restart
    log_success "Services restarted"
    show_status
}

# Update services
update_services() {
    log_info "Updating services..."
    docker compose pull
    docker compose up -d --build
    log_success "Services updated"
    show_status
}

# Open shell in OpenClaw
open_shell() {
    log_info "Opening shell in OpenClaw container..."
    docker compose exec openclaw /bin/bash
}

# Configure OpenClaw
configure_openclaw() {
    log_info "Running OpenClaw configuration..."
    docker compose exec -it openclaw openclaw configure
}

# Show token
show_token() {
    local token=$(docker compose exec openclaw cat /home/node/.openclaw/openclaw.json 2>/dev/null | grep -o '"token": "[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$token" ]; then
        echo ""
        log_info "OpenClaw Gateway Token:"
        echo ""
        echo "  $token"
        echo ""
        echo "Use this token in the Control UI (Settings → Token)"
        echo ""
    else
        log_error "Could not retrieve token. Is OpenClaw running?"
        exit 1
    fi
}

# Create backup
create_backup() {
    local backup_dir="$HOME/nazar/backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/nazar-backup-$timestamp.tar.gz"
    
    mkdir -p "$backup_dir"
    
    log_info "Creating backup..."
    
    # Stop services for consistent backup
    docker compose stop
    
    # Create backup
    VAULT_PATH=$(get_vault_path)
    NAZAR_BASE=$(dirname "$VAULT_PATH")
    
    tar -czf "$backup_file" \
        -C "$NAZAR_BASE" \
        vault \
        .openclaw \
        syncthing \
        2>/dev/null || {
        log_error "Backup failed"
        docker compose start
        exit 1
    }
    
    # Start services
    docker compose start
    
    log_success "Backup created: $backup_file"
    
    # List backups
    echo ""
    log_info "Existing backups:"
    ls -lh "$backup_dir"
}

# Restore from backup
restore_backup() {
    local backup_file=$1
    
    if [ -z "$backup_file" ]; then
        log_error "Please specify backup file"
        echo "Usage: nazar-cli restore <backup-file>"
        exit 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        # Try in backups directory
        backup_file="$HOME/nazar/backups/$backup_file"
        if [ ! -f "$backup_file" ]; then
            log_error "Backup file not found: $backup_file"
            exit 1
        fi
    fi
    
    log_warn "This will overwrite current data!"
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "Restore cancelled"
        exit 0
    fi
    
    log_info "Restoring from backup..."
    
    # Stop services
    docker compose down
    
    # Get vault path
    VAULT_PATH=$(get_vault_path)
    NAZAR_BASE=$(dirname "$VAULT_PATH")
    
    # Extract backup
    tar -xzf "$backup_file" -C "$NAZAR_BASE"
    
    # Fix permissions
    chown -R $(id -u):$(id -g) "$NAZAR_BASE"
    
    # Start services
    docker compose up -d
    
    log_success "Restore complete"
}

# Show Syncthing ID
show_syncthing_id() {
    log_info "Syncthing Device ID:"
    docker compose exec syncthing syncthing cli show system | grep "myID" || {
        log_warn "Could not get Device ID. Is Syncthing running?"
        exit 1
    }
}

# Show SSH tunnel command
show_tunnel() {
    local vps_ip=$(hostname -I | awk '{print $1}')
    local user=$(whoami)
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║              SSH Tunnel Commands                              ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "OpenClaw Gateway:"
    echo ""
    echo "  ssh -N -L 18789:localhost:18789 $user@$vps_ip"
    echo ""
    echo "  Then open: http://localhost:18789"
    echo ""
    log_info "Syncthing GUI:"
    echo ""
    echo "  ssh -N -L 8384:localhost:8384 $user@$vps_ip"
    echo ""
    echo "  Then open: http://localhost:8384"
    echo ""
    log_info "Both services (single command):"
    echo ""
    echo "  ssh -N -L 18789:localhost:18789 -L 8384:localhost:8384 $user@$vps_ip"
    echo ""
    log_info "To run in background, add -f flag:"
    echo ""
    echo "  ssh -f -N -L 18789:localhost:18789 -L 8384:localhost:8384 $user@$vps_ip"
    echo ""
}

# Open vault directory
open_vault() {
    VAULT_PATH=$(get_vault_path)
    log_info "Vault location: $VAULT_PATH"
    cd "$VAULT_PATH" || exit 1
    $SHELL
}

# Clean Docker resources
clean_docker() {
    log_warn "This will remove unused Docker images, containers, and volumes"
    read -p "Continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "Cancelled"
        exit 0
    fi
    
    docker system prune -f
    docker volume prune -f
    log_success "Docker cleanup complete"
}

# Main command handler
case "${1:-}" in
    status|st)
        show_status
        ;;
    logs|log|l)
        show_logs "$2"
        ;;
    start|up)
        start_services
        ;;
    stop|down)
        stop_services
        ;;
    restart|reboot)
        restart_services
        ;;
    update|upgrade)
        update_services
        ;;
    shell|sh|exec)
        open_shell
        ;;
    configure|config)
        configure_openclaw
        ;;
    token)
        show_token
        ;;
    backup)
        create_backup
        ;;
    restore)
        restore_backup "$2"
        ;;
    syncthing-id|id)
        show_syncthing_id
        ;;
    tunnel|ssh)
        show_tunnel
        ;;
    vault|cd)
        open_vault
        ;;
    clean|prune)
        clean_docker
        ;;
    security|audit)
        sudo nazar-security-audit
        ;;
    security|audit)
        sudo nazar-security-audit
        ;;
    security|audit)
        sudo nazar-security-audit
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        log_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
