#!/bin/bash
#
# Nazar AI Setup - AI Agent Optimized VPS Provisioning
# Designed for Claude Code, Kimi Code, and other AI agents
#
# Usage:
#   nazar-ai-setup status              # Show current setup state
#   nazar-ai-setup validate            # Pre-flight checks
#   nazar-ai-setup run [phase]         # Run setup (optionally from phase)
#   nazar-ai-setup --json status       # Machine-readable output
#
# Features:
#   - Checkpoint/resume: Tracks progress in ~/.nazar-setup-state
#   - JSON output: --json flag for machine parsing
#   - Idempotent: Safe to re-run any phase
#   - Validation: Each phase verifies previous phases
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_VERSION="1.0.0"
STATE_FILE="$HOME/.nazar-setup-state"
LOG_FILE="$HOME/.nazar-setup-log"
NAZAR_BASE="$HOME/nazar"

# Phases in order
PHASES=("validate" "user" "security" "docker" "services" "tailscale" "verify")

# Colors (disabled in JSON mode)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# OUTPUT FUNCTIONS
# ============================================================================

JSON_MODE=false

log_info() { 
    if [[ "$JSON_MODE" == "true" ]]; then
        echo "{\"level\":\"info\",\"message\":\"$1\",\"timestamp\":\"$(date -Iseconds)\"}"
    else
        echo -e "${BLUE}[INFO]${NC} $1" 
    fi
}

log_success() { 
    if [[ "$JSON_MODE" == "true" ]]; then
        echo "{\"level\":\"success\",\"message\":\"$1\",\"timestamp\":\"$(date -Iseconds)\"}"
    else
        echo -e "${GREEN}[OK]${NC} $1" 
    fi
}

log_warn() { 
    if [[ "$JSON_MODE" == "true" ]]; then
        echo "{\"level\":\"warn\",\"message\":\"$1\",\"timestamp\":\"$(date -Iseconds)\"}"
    else
        echo -e "${YELLOW}[WARN]${NC} $1" 
    fi
}

log_error() { 
    if [[ "$JSON_MODE" == "true" ]]; then
        echo "{\"level\":\"error\",\"message\":\"$1\",\"timestamp\":\"$(date -Iseconds)\"}"
    else
        echo -e "${RED}[ERROR]${NC} $1" 
    fi
}

log_step() { 
    if [[ "$JSON_MODE" == "true" ]]; then
        echo "{\"level\":\"step\",\"phase\":\"$1\",\"message\":\"$2\",\"timestamp\":\"$(date -Iseconds)\"}"
    else
        echo -e "${CYAN}[STEP]${NC} $2" 
    fi
}

# ============================================================================
# STATE MANAGEMENT
# ============================================================================

init_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        cat > "$STATE_FILE" << 'EOF'
{
  "version": "1.0.0",
  "started": null,
  "completed": null,
  "current_phase": null,
  "phases": {
    "validate": { "status": "pending", "started": null, "completed": null, "result": null },
    "user": { "status": "pending", "started": null, "completed": null, "result": null },
    "security": { "status": "pending", "started": null, "completed": null, "result": null },
    "docker": { "status": "pending", "started": null, "completed": null, "result": null },
    "services": { "status": "pending", "started": null, "completed": null, "result": null },
    "tailscale": { "status": "pending", "started": null, "completed": null, "result": null },
    "verify": { "status": "pending", "started": null, "completed": null, "result": null }
  },
  "config": {
    "deployment_mode": null,
    "hostname": null,
    "tailscale_authkey": null
  }
}
EOF
    fi
}

get_state() {
    local key="$1"
    if [[ -f "$STATE_FILE" ]]; then
        jq -r "$key" "$STATE_FILE" 2>/dev/null || echo "null"
    else
        echo "null"
    fi
}

set_state() {
    local key="$1"
    local value="$2"
    local tmpfile="$(mktemp)"
    jq "$key = $value" "$STATE_FILE" > "$tmpfile" && mv "$tmpfile" "$STATE_FILE"
}

mark_phase() {
    local phase="$1"
    local status="$2"
    local result="${3:-null}"
    
    set_state ".phases.$phase.status" "\"$status\""
    
    if [[ "$status" == "running" ]]; then
        set_state ".phases.$phase.started" "\"$(date -Iseconds)\""
        set_state ".current_phase" "\"$phase\""
    elif [[ "$status" == "completed" ]] || [[ "$status" == "failed" ]]; then
        set_state ".phases.$phase.completed" "\"$(date -Iseconds)\""
        if [[ "$result" != "null" ]]; then
            set_state ".phases.$phase.result" "\"$result\""
        fi
    fi
    
    # Log to file
    echo "$(date -Iseconds) [$status] Phase: $phase - $result" >> "$LOG_FILE"
}

# ============================================================================
# STATUS COMMAND
# ============================================================================

cmd_status() {
    if [[ ! -f "$STATE_FILE" ]]; then
        if [[ "$JSON_MODE" == "true" ]]; then
            echo '{"setup_started": false, "message": "Setup has not been started"}'
        else
            echo "Setup has not been started."
            echo "Run: nazar-ai-setup run"
        fi
        return 0
    fi
    
    if [[ "$JSON_MODE" == "true" ]]; then
        jq '{
            setup_started: (.started != null),
            setup_completed: (.completed != null),
            current_phase: .current_phase,
            phases: .phases
        }' "$STATE_FILE"
    else
        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║              Nazar AI Setup Status                           ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""
        
        local current_phase
        current_phase=$(get_state ".current_phase")
        
        echo "Current Phase: ${current_phase:-"Not started"}"
        echo ""
        echo "Phase Status:"
        echo "-------------"
        
        for phase in "${PHASES[@]}"; do
            local status
            status=$(get_state ".phases.$phase.status")
            local symbol="⏳"
            local color="$YELLOW"
            
            case "$status" in
                "completed")
                    symbol="✓"
                    color="$GREEN"
                    ;;
                "running")
                    symbol="►"
                    color="$CYAN"
                    ;;
                "failed")
                    symbol="✗"
                    color="$RED"
                    ;;
            esac
            
            printf "  ${color}%s${NC} %-12s [%s]\n" "$symbol" "$phase" "$status"
        done
        
        echo ""
        echo "Next Action:"
        case "$current_phase" in
            "null"|"")
                echo "  Run: nazar-ai-setup run"
                ;;
            "validate")
                echo "  Validation in progress..."
                ;;
            "user")
                echo "  User setup in progress..."
                ;;
            "security")
                echo "  Security hardening in progress..."
                ;;
            "docker")
                echo "  Docker installation in progress..."
                ;;
            "services")
                echo "  Service deployment in progress..."
                ;;
            "tailscale")
                echo "  Tailscale setup in progress..."
                echo "  Note: Requires manual auth URL confirmation"
                ;;
            "verify")
                echo "  Verification in progress..."
                ;;
            *)
                if [[ "$current_phase" == "completed" ]]; then
                    echo "  ✓ Setup complete!"
                    echo ""
                    echo "  Access your services:"
                    echo "    - OpenClaw Gateway: http://localhost:18789 (via SSH tunnel)"
                    echo "    - Syncthing GUI: http://localhost:8384 (via SSH tunnel)"
                fi
                ;;
        esac
        echo ""
    fi
}

# ============================================================================
# VALIDATE COMMAND
# ============================================================================

cmd_validate() {
    log_step "validate" "Running pre-flight validation"
    mark_phase "validate" "running"
    
    local errors=()
    local warnings=()
    
    # Check 1: OS
    if [[ -f /etc/os-release ]]; then
        local os_name
        os_name=$(grep "^NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
        if [[ "$os_name" =~ Debian ]]; then
            log_success "OS: $os_name"
        else
            errors+=("OS must be Debian (found: $os_name)")
        fi
    else
        errors+=("Cannot detect OS")
    fi
    
    # Check 2: Root access (for some phases)
    if [[ $EUID -eq 0 ]]; then
        log_warn "Running as root. Some phases require the 'debian' user."
        warnings+=("Running as root - 'debian' user needed for service deployment")
    fi
    
    # Check 3: debian user exists (if not root)
    if [[ $EUID -ne 0 ]] && ! id "debian" &>/dev/null; then
        if [[ "$USER" != "debian" ]]; then
            warnings+=("'debian' user not found - will be created if running as root")
        fi
    fi
    
    # Check 4: Internet connectivity
    if curl -fsSL https://github.com > /dev/null 2>&1; then
        log_success "Internet connectivity: OK"
    else
        errors+=("No internet connectivity")
    fi
    
    # Check 5: Disk space
    local available
    available=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ "$available" -ge 5 ]]; then
        log_success "Disk space: ${available}GB available"
    else
        warnings+=("Low disk space: ${available}GB (recommended: 5GB+)")
    fi
    
    # Check 6: SSH key (for security phase)
    if [[ -f "$HOME/.ssh/authorized_keys" ]] || [[ -f /root/.ssh/authorized_keys ]]; then
        log_success "SSH keys: Found"
    else
        warnings+=("No SSH keys found - password auth will be disabled (potential lockout risk)")
    fi
    
    # Check 7: Required tools
    if command -v jq &> /dev/null; then
        log_success "Tools: jq available"
    else
        log_info "Tools: jq not found (will be installed)"
    fi
    
    # Output results
    local result="success"
    if [[ ${#errors[@]} -gt 0 ]]; then
        result="failed"
        log_error "Validation FAILED:"
        for err in "${errors[@]}"; do
            log_error "  - $err"
        done
    fi
    
    if [[ ${#warnings[@]} -gt 0 ]]; then
        log_warn "Warnings:"
        for warn in "${warnings[@]}"; do
            log_warn "  - $warn"
        done
    fi
    
    if [[ "$result" == "success" ]]; then
        log_success "Validation passed"
        mark_phase "validate" "completed" "success"
    else
        mark_phase "validate" "failed" "$(IFS=,; echo "${errors[*]}")"
        return 1
    fi
    
    # JSON output
    if [[ "$JSON_MODE" == "true" ]]; then
        jq -n \
            --arg result "$result" \
            --argjson errors "$(printf '%s\n' "${errors[@]}" | jq -R . | jq -s .)" \
            --argjson warnings "$(printf '%s\n' "${warnings[@]}" | jq -R . | jq -s .)" \
            '{result: $result, errors: $errors, warnings: $warnings}'
    fi
}

# ============================================================================
# PHASE RUNNERS
# ============================================================================

phase_user() {
    log_step "user" "Setting up debian user"
    mark_phase "user" "running"
    
    if [[ $EUID -ne 0 ]]; then
        log_error "User setup must run as root"
        mark_phase "user" "failed" "not_root"
        return 1
    fi
    
    # Create debian user if doesn't exist
    if ! id "debian" &>/dev/null; then
        log_info "Creating debian user..."
        adduser --disabled-password --gecos "" debian
        usermod -aG sudo debian
    fi
    
    # Ensure passwordless sudo
    echo "debian ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/debian
    chmod 0440 /etc/sudoers.d/debian
    
    # Copy SSH keys from root if present
    if [[ -f /root/.ssh/authorized_keys ]] && [[ ! -f /home/debian/.ssh/authorized_keys ]]; then
        log_info "Copying SSH keys to debian user..."
        mkdir -p /home/debian/.ssh
        cp /root/.ssh/authorized_keys /home/debian/.ssh/
        chown -R debian:debian /home/debian/.ssh
        chmod 700 /home/debian/.ssh
        chmod 600 /home/debian/.ssh/authorized_keys
    fi
    
    log_success "User 'debian' ready"
    mark_phase "user" "completed" "debian_user_configured"
}

phase_security() {
    log_step "security" "Applying security hardening"
    mark_phase "security" "running"
    
    # Run the secure-vps script
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if [[ -f "$script_dir/secure-vps.sh" ]]; then
        bash "$script_dir/secure-vps.sh"
        log_success "Security hardening applied"
        mark_phase "security" "completed" "hardening_applied"
    else
        # Download and run
        log_info "Downloading security script..."
        curl -fsSL "https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup-security.sh" | bash
        log_success "Security hardening applied"
        mark_phase "security" "completed" "hardening_applied"
    fi
}

phase_docker() {
    log_step "docker" "Installing Docker"
    mark_phase "docker" "running"
    
    if command -v docker &> /dev/null; then
        log_success "Docker already installed"
    else
        log_info "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        sudo systemctl enable docker
        sudo systemctl start docker
    fi
    
    # Verify
    if docker --version &> /dev/null; then
        log_success "Docker: $(docker --version)"
    else
        log_error "Docker installation failed"
        mark_phase "docker" "failed" "install_failed"
        return 1
    fi
    
    # Add debian to docker group
    sudo usermod -aG docker debian
    
    # Install jq if not present
    if ! command -v jq &> /dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq jq
    fi
    
    mark_phase "docker" "completed" "docker_installed"
}

phase_services() {
    log_step "services" "Deploying Nazar services"
    mark_phase "services" "running"
    
    # Switch to debian user for service deployment
    if [[ "$USER" != "debian" ]]; then
        log_info "Switching to debian user for service deployment..."
        log_info "Please run as debian user: su - debian"
        log_info "Then: nazar-ai-setup run services"
        mark_phase "services" "failed" "wrong_user"
        return 1
    fi
    
    # Run the main setup script
    if [[ -f "$HOME/nazar-deploy/docker/setup.sh" ]]; then
        bash "$HOME/nazar-deploy/docker/setup.sh"
    else
        curl -fsSL https://raw.githubusercontent.com/alexradunet/easy-para-system-claw-vps/master/docker/setup.sh | bash
    fi
    
    log_success "Services deployed"
    mark_phase "services" "completed" "services_running"
}

phase_tailscale() {
    log_step "tailscale" "Setting up Tailscale"
    mark_phase "tailscale" "running"
    
    if command -v tailscale &> /dev/null; then
        log_success "Tailscale already installed"
        if tailscale status &> /dev/null; then
            log_success "Tailscale already connected"
            mark_phase "tailscale" "completed" "already_connected"
            return 0
        fi
    else
        log_info "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    
    # Check for auth key in state
    local authkey
    authkey=$(get_state ".config.tailscale_authkey")
    
    if [[ "$authkey" != "null" && -n "$authkey" ]]; then
        log_info "Starting Tailscale with auth key..."
        sudo tailscale up --authkey "$authkey"
    else
        log_info "Starting Tailscale (manual auth required)..."
        log_warn "IMPORTANT: Tailscale will display an auth URL."
        log_warn "The user must open this URL in their browser to authorize."
        echo ""
        sudo tailscale up
    fi
    
    # Wait for connection
    local attempts=0
    while ! tailscale status &> /dev/null && [[ $attempts -lt 30 ]]; do
        sleep 2
        attempts=$((attempts + 1))
    done
    
    if tailscale status &> /dev/null; then
        local ts_ip
        ts_ip=$(tailscale ip -4)
        log_success "Tailscale connected: $ts_ip"
        mark_phase "tailscale" "completed" "connected:$ts_ip"
    else
        log_warn "Tailscale installation complete but not yet authorized"
        mark_phase "tailscale" "completed" "pending_auth"
    fi
}

phase_verify() {
    log_step "verify" "Running final verification"
    mark_phase "verify" "running"
    
    local checks_passed=0
    local checks_total=0
    
    # Check 1: Docker running
    ((checks_total++))
    if docker ps &> /dev/null; then
        log_success "✓ Docker daemon running"
        ((checks_passed++))
    else
        log_error "✗ Docker daemon not running"
    fi
    
    # Check 2: Containers up
    ((checks_total++))
    if docker compose -f ~/nazar/docker/docker-compose.yml ps 2>/dev/null | grep -q "Up"; then
        log_success "✓ Containers running"
        ((checks_passed++))
    else
        log_error "✗ Containers not running"
    fi
    
    # Check 3: Vault directory
    ((checks_total++))
    if [[ -d ~/nazar/vault/00-inbox ]]; then
        log_success "✓ Vault structure present"
        ((checks_passed++))
    else
        log_warn "✗ Vault structure incomplete"
    fi
    
    # Check 4: OpenClaw config
    ((checks_total++))
    if [[ -f ~/nazar/.openclaw/openclaw.json ]]; then
        log_success "✓ OpenClaw configured"
        ((checks_passed++))
    else
        log_error "✗ OpenClaw config missing"
    fi
    
    # Check 5: SSH hardened
    ((checks_total++))
    if [[ -f /etc/ssh/sshd_config.d/nazar.conf ]]; then
        log_success "✓ SSH hardened"
        ((checks_passed++))
    else
        log_warn "✗ SSH hardening not applied"
    fi
    
    echo ""
    log_info "Verification: $checks_passed/$checks_total checks passed"
    
    if [[ $checks_passed -eq $checks_total ]]; then
        log_success "All verification checks passed!"
        mark_phase "verify" "completed" "all_passed"
        set_state ".completed" "\"$(date -Iseconds)\""
    else
        log_warn "Some checks failed. Review the output above."
        mark_phase "verify" "completed" "$checks_passed/$checks_total"
    fi
}

# ============================================================================
# RUN COMMAND
# ============================================================================

cmd_run() {
    local start_phase="${1:-}"
    
    # Initialize state
    init_state
    
    if [[ -z "$(get_state ".started")" ]] || [[ "$(get_state ".started")" == "null" ]]; then
        set_state ".started" "\"$(date -Iseconds)\""
    fi
    
    # Determine starting point
    local start_idx=0
    if [[ -n "$start_phase" ]]; then
        for i in "${!PHASES[@]}"; do
            if [[ "${PHASES[$i]}" == "$start_phase" ]]; then
                start_idx=$i
                break
            fi
        done
    fi
    
    # Run phases
    for ((i=start_idx; i<${#PHASES[@]}; i++)); do
        local phase="${PHASES[$i]}"
        
        # Skip if already completed (unless explicitly requested)
        if [[ -n "$start_phase" ]] || [[ "$(get_state ".phases.$phase.status")" != "completed" ]]; then
            case "$phase" in
                "validate") cmd_validate || return 1 ;;
                "user") phase_user || return 1 ;;
                "security") phase_security || return 1 ;;
                "docker") phase_docker || return 1 ;;
                "services") phase_services || return 1 ;;
                "tailscale") phase_tailscale || return 1 ;;
                "verify") phase_verify || return 1 ;;
            esac
        else
            log_info "Skipping $phase (already completed)"
        fi
    done
    
    if [[ "$JSON_MODE" != "true" ]]; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║              Setup Complete!                                 ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Next steps:"
        echo "  1. Configure Syncthing: http://localhost:8384 (via SSH tunnel)"
        echo "  2. Configure OpenClaw: docker compose exec -it openclaw openclaw configure"
        echo ""
        echo "Management: nazar-cli status | nazar-cli logs | nazar-cli backup"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

usage() {
    cat << 'EOF'
Usage: nazar-ai-setup [OPTIONS] COMMAND [ARGS]

AI-optimized VPS setup for Nazar Second Brain.
Designed for Claude Code, Kimi Code, and other AI agents.

Commands:
    status              Show current setup state
    validate            Run pre-flight validation
    run [phase]         Run setup from beginning or specific phase
    reset               Reset setup state (dangerous)

Phases (for 'run' command):
    validate    - Pre-flight checks
    user        - Create/configure debian user
    security    - Apply security hardening
    docker      - Install Docker
    services    - Deploy OpenClaw + Syncthing
    tailscale   - Setup Tailscale VPN
    verify      - Final verification

Options:
    --json      Output in JSON format for machine parsing
    --version   Show version
    --help      Show this help

Examples:
    nazar-ai-setup status              # Human-readable status
    nazar-ai-setup --json status       # Machine-readable status
    nazar-ai-setup validate            # Check prerequisites
    nazar-ai-setup run                 # Full setup
    nazar-ai-setup run docker          # Resume from docker phase

State Tracking:
    Setup progress is tracked in ~/.nazar-setup-state (JSON).
    Safe to re-run; completed phases are skipped by default.
EOF
}

main() {
    local command=""
    local command_args=""
    
    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                JSON_MODE=true
                shift
                ;;
            --version)
                echo "nazar-ai-setup v$SCRIPT_VERSION"
                exit 0
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            status|validate|run|reset)
                command="$1"
                shift
                command_args="$@"
                break
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Require jq for state management
    if [[ -n "$command" ]] && ! command -v jq &> /dev/null && [[ "$command" != "status" ]]; then
        echo "Installing jq (required for state management)..."
        if [[ $EUID -eq 0 ]]; then
            apt-get update -qq && apt-get install -y -qq jq
        else
            sudo apt-get update -qq && sudo apt-get install -y -qq jq
        fi
    fi
    
    case "$command" in
        status)
            cmd_status
            ;;
        validate)
            cmd_validate
            ;;
        run)
            cmd_run $command_args
            ;;
        reset)
            rm -f "$STATE_FILE"
            log_success "Setup state reset"
            ;;
        "")
            usage
            exit 1
            ;;
    esac
}

main "$@"
