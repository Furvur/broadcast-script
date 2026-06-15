#!/bin/bash

# Smoke Test for Broadcast Installation
#
# Spins up disposable Ubuntu VMs (24.04 and 26.04 by default), runs the
# real installer on each, and verifies the system boots successfully.
#
# By default the VM clones the canonical repo from
# https://github.com/send-broadcast/broadcast-script.git, matching what
# real end users do. Use --local to test the current working tree
# (uncommitted changes included).
#
# Usage:
#   ./tests/smoke/test_multipass_smoke.sh                 # Basic smoke test (both versions)
#   ./tests/smoke/test_multipass_smoke.sh --ubuntu 24.04  # Test only 24.04
#   ./tests/smoke/test_multipass_smoke.sh --ubuntu 26.04  # Test only 26.04
#   ./tests/smoke/test_multipass_smoke.sh --local         # Test local working tree instead of cloning remote
#   ./tests/smoke/test_multipass_smoke.sh --no-cleanup    # Keep VM for debugging
#   ./tests/smoke/test_multipass_smoke.sh --test-reboot   # Verify reboot recovery
#   ./tests/smoke/test_multipass_smoke.sh --verbose       # Show all command output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Canonical repo URL — the test clones this by default so it exercises
# what real end users actually install.
BROADCAST_REPO_URL="https://github.com/send-broadcast/broadcast-script.git"

# Ubuntu versions to exercise. Override with --ubuntu VERSION.
DEFAULT_UBUNTU_VERSIONS=("24.04" "26.04")
UBUNTU_VERSIONS=("${DEFAULT_UBUNTU_VERSIONS[@]}")

# Per-iteration state (set inside the version loop)
UBUNTU_VERSION=""
VAGRANT_DIR=""

# CLI flags
FLAG_NO_CLEANUP=false
FLAG_TEST_REBOOT=false
FLAG_TEST_UPGRADE=false
FLAG_TEST_REAL_UPGRADE=false
FLAG_VERBOSE=false
FLAG_LOCAL=false
FROM_REF=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters (aggregated across all Ubuntu versions)
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Per-version results — parallel arrays
VERSION_NAMES=()
VERSION_RUN=()
VERSION_PASSED=()
VERSION_FAILED=()

#######################
# Helper Functions
#######################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_test() {
    echo -e "\n${YELLOW}[TEST]${NC} $1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Run a command on the VM as root via vagrant ssh
vm_exec_root() {
    local cmd="$1"
    if [ "$FLAG_VERBOSE" = true ]; then
        cd "$VAGRANT_DIR" && vagrant ssh -c "sudo bash -c '$cmd'" 2>&1
    else
        cd "$VAGRANT_DIR" && vagrant ssh -c "sudo bash -c '$cmd'" 2>/dev/null
    fi
}

#######################
# Credential Loading
#######################

load_credentials() {
    local env_file="$SCRIPT_DIR/.smoke-test.env"

    # Load from file if it exists (won't overwrite existing env vars)
    if [ -f "$env_file" ]; then
        log_info "Loading credentials from .smoke-test.env"
        set +u
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
            # Trim whitespace
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            # Only set if not already in environment
            if [ -z "${!key:-}" ]; then
                export "$key=$value"
            fi
        done < "$env_file"
        set -u
    fi

    # Only the license key is required — registry creds are fetched from the API
    if [ -z "${BROADCAST_LICENSE_KEY:-}" ]; then
        echo -e "${RED}Error: BROADCAST_LICENSE_KEY is required.${NC}"
        echo ""
        echo "Either set it as an environment variable or create:"
        echo "  $env_file"
        echo ""
        echo "See .smoke-test.env.sample for the template."
        exit 1
    fi

    # If registry credentials weren't provided, fetch them via the license API
    if [ -z "${BROADCAST_REGISTRY_URL:-}" ] || [ -z "${BROADCAST_REGISTRY_LOGIN:-}" ] || [ -z "${BROADCAST_REGISTRY_PASSWORD:-}" ]; then
        log_info "Fetching registry credentials from license API..."
        fetch_registry_credentials
    fi
}

fetch_registry_credentials() {
    local domain="smoke-test.local"
    local tmpfile
    tmpfile=$(mktemp)

    local http_code
    http_code=$(curl -s -w "%{http_code}" -o "$tmpfile" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"key\":\"${BROADCAST_LICENSE_KEY}\", \"domain\":\"${domain}\"}" \
        https://sendbroadcast.net/license/check)

    if [ "$http_code" != "200" ]; then
        local body
        body=$(cat "$tmpfile")
        rm -f "$tmpfile"
        echo -e "${RED}Error: License validation failed (HTTP $http_code)${NC}"
        [ -n "$body" ] && echo "  Response: $body"
        exit 1
    fi

    local response
    response=$(cat "$tmpfile")
    rm -f "$tmpfile"

    # Parse registry credentials from the response
    BROADCAST_REGISTRY_URL=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['registry_url'])" 2>/dev/null) || true
    BROADCAST_REGISTRY_LOGIN=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['registry_login'])" 2>/dev/null) || true
    BROADCAST_REGISTRY_PASSWORD=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['registry_password'])" 2>/dev/null) || true

    if [ -z "$BROADCAST_REGISTRY_URL" ] || [ -z "$BROADCAST_REGISTRY_LOGIN" ] || [ -z "$BROADCAST_REGISTRY_PASSWORD" ]; then
        echo -e "${RED}Error: Failed to parse registry credentials from license API response.${NC}"
        exit 1
    fi

    export BROADCAST_REGISTRY_URL BROADCAST_REGISTRY_LOGIN BROADCAST_REGISTRY_PASSWORD
    log_info "Registry credentials fetched successfully."
}

#######################
# Cleanup
#######################

cleanup() {
    # No active VM yet (e.g. credential check failed before the loop started)
    if [ -z "$VAGRANT_DIR" ] || [ ! -d "$VAGRANT_DIR" ]; then
        return
    fi

    if [ "$FLAG_NO_CLEANUP" = true ]; then
        log_warn "Skipping cleanup (--no-cleanup). VM is still running in $VAGRANT_DIR"
        log_warn "To clean up manually: cd $VAGRANT_DIR && vagrant destroy -f"
        return
    fi

    log_info "Cleaning up VM (Ubuntu ${UBUNTU_VERSION})..."
    cd "$VAGRANT_DIR" && vagrant destroy -f 2>/dev/null || true
    rm -rf "$VAGRANT_DIR"
}

#######################
# Phase 1: Setup VM
#######################

setup_vm() {
    log_info "=== Phase 1: Setup VM (Ubuntu ${UBUNTU_VERSION}) ==="

    # Check vagrant is installed
    if ! command -v vagrant &>/dev/null; then
        echo -e "${RED}Error: Vagrant is not installed.${NC}"
        echo "Install it with: brew install vagrant"
        exit 1
    fi

    # Create Vagrant working directory
    mkdir -p "$VAGRANT_DIR"

    # Detect host arch and pick QEMU machine flags. macOS uses Apple's HVF
    # accelerator on both Apple Silicon (aarch64) and Intel (x86_64).
    local host_arch qemu_arch qemu_machine qemu_ssh_port
    host_arch=$(uname -m)
    if [ "$host_arch" = "arm64" ] || [ "$host_arch" = "aarch64" ]; then
        qemu_arch="aarch64"
        qemu_machine="virt,accel=hvf,highmem=on"
    else
        qemu_arch="x86_64"
        qemu_machine="q35,accel=hvf"
    fi

    # Derive a per-version SSH port so back-to-back runs don't collide on the
    # vagrant-qemu default (50022). Major version offset: 24.04 -> 50024, 26.04 -> 50026.
    qemu_ssh_port=$((50000 + ${UBUNTU_VERSION%%.*}))

    # Generate Vagrantfile — provisioning differs depending on whether we are
    # cloning the canonical remote (default) or copying the local working tree.
    if [ "$FLAG_LOCAL" = true ]; then
        log_info "Repo source: local working tree ($PROJECT_ROOT)"
        cat > "$VAGRANT_DIR/Vagrantfile" <<'VAGRANTEOF'
Vagrant.configure("2") do |config|
  config.vm.box = "cloud-image/ubuntu-UBUNTU_VERSION_PLACEHOLDER"
  config.vm.hostname = "broadcast-smoke-test"

  config.vm.provider "qemu" do |qe|
    qe.arch = "QEMU_ARCH_PLACEHOLDER"
    qe.machine = "QEMU_MACHINE_PLACEHOLDER"
    qe.cpu = "host"
    qe.smp = "cpus=2,sockets=1,cores=2,threads=1"
    qe.memory = "2048M"
    qe.net_device = "virtio-net-pci"
    qe.ssh_port = "QEMU_SSH_PORT_PLACEHOLDER"
  end

  # Disable the default /vagrant share — QEMU does not support virtfs by default
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # Share local working tree via rsync (cloud-image boxes have rsync preinstalled)
  config.vm.synced_folder "BROADCAST_REPO_PATH", "/tmp/broadcast-repo", type: "rsync"

  config.vm.provision "shell", inline: <<-SHELL
    rm -rf /opt/broadcast
    mkdir -p /opt/broadcast
    cp -a /tmp/broadcast-repo/. /opt/broadcast/
  SHELL
end
VAGRANTEOF
        sed -i '' "s|BROADCAST_REPO_PATH|${PROJECT_ROOT}|" "$VAGRANT_DIR/Vagrantfile"
    else
        log_info "Repo source: ${BROADCAST_REPO_URL}"
        cat > "$VAGRANT_DIR/Vagrantfile" <<'VAGRANTEOF'
Vagrant.configure("2") do |config|
  config.vm.box = "cloud-image/ubuntu-UBUNTU_VERSION_PLACEHOLDER"
  config.vm.hostname = "broadcast-smoke-test"

  config.vm.provider "qemu" do |qe|
    qe.arch = "QEMU_ARCH_PLACEHOLDER"
    qe.machine = "QEMU_MACHINE_PLACEHOLDER"
    qe.cpu = "host"
    qe.smp = "cpus=2,sockets=1,cores=2,threads=1"
    qe.memory = "2048M"
    qe.net_device = "virtio-net-pci"
    qe.ssh_port = "QEMU_SSH_PORT_PLACEHOLDER"
  end

  # Disable the default /vagrant share — QEMU does not support virtfs by default
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # Clone the canonical repo — matches what real end users install
  config.vm.provision "shell", inline: <<-SHELL
    set -e
    if ! command -v git >/dev/null 2>&1; then
      apt-get update -qq
      apt-get install -y -qq git
    fi
    rm -rf /opt/broadcast
    git clone BROADCAST_REPO_URL_PLACEHOLDER /opt/broadcast
  SHELL
end
VAGRANTEOF
        sed -i '' "s|BROADCAST_REPO_URL_PLACEHOLDER|${BROADCAST_REPO_URL}|" "$VAGRANT_DIR/Vagrantfile"
    fi

    sed -i '' "s|UBUNTU_VERSION_PLACEHOLDER|${UBUNTU_VERSION}|" "$VAGRANT_DIR/Vagrantfile"
    sed -i '' "s|QEMU_ARCH_PLACEHOLDER|${qemu_arch}|" "$VAGRANT_DIR/Vagrantfile"
    sed -i '' "s|QEMU_MACHINE_PLACEHOLDER|${qemu_machine}|" "$VAGRANT_DIR/Vagrantfile"
    sed -i '' "s|QEMU_SSH_PORT_PLACEHOLDER|${qemu_ssh_port}|" "$VAGRANT_DIR/Vagrantfile"

    # Launch VM (QEMU provider)
    log_info "Launching Ubuntu ${UBUNTU_VERSION} VM (qemu/${qemu_arch}, ssh port ${qemu_ssh_port})..."
    cd "$VAGRANT_DIR" && vagrant up --provider=qemu

    log_info "VM is ready."
}

#######################
# Phase 2: Prepare Installation
#######################

prepare_installation() {
    log_info "=== Phase 2: Prepare Installation ==="

    # Optionally roll /opt/broadcast back to an older revision so a later
    # `broadcast.sh upgrade` performs a genuine old->new upgrade (its `git pull`
    # then advances the scripts). Remote mode only — local mode is not a clone.
    if [ -n "$FROM_REF" ] && [ "$FLAG_LOCAL" != true ]; then
        log_info "Resetting /opt/broadcast to base ref ${FROM_REF} for pre-upgrade install..."
        vm_exec_root "git -C /opt/broadcast reset --hard ${FROM_REF}"
    fi

    # Create required directories
    log_info "Creating required directories..."
    vm_exec_root "mkdir -p /opt/broadcast/{app,db,ssl,logs,logs/cron}"

    # Pre-create config files to bypass interactive prompts
    log_info "Pre-creating config files..."

    # .domain — bypasses check_installation_domain()
    vm_exec_root "echo smoke-test.local > /opt/broadcast/.domain"

    # .license — bypasses check_license()
    vm_exec_root "echo ${BROADCAST_LICENSE_KEY} > /opt/broadcast/.license"

    # .env — registry credentials for docker login (bypasses validate_license)
    vm_exec_root "printf \"BROADCAST_REGISTRY_URL=${BROADCAST_REGISTRY_URL}\nBROADCAST_REGISTRY_LOGIN=${BROADCAST_REGISTRY_LOGIN}\nBROADCAST_REGISTRY_PASSWORD=${BROADCAST_REGISTRY_PASSWORD}\n\" > /opt/broadcast/.env"

    # Patch install.sh: replace 'sudo reboot' with a no-op
    log_info "Patching install.sh to skip reboot..."
    vm_exec_root "sed -i s/sudo\\ reboot/echo\\ SMOKE_TEST_SKIP_REBOOT/ /opt/broadcast/scripts/install.sh"

    # Make broadcast.sh executable
    vm_exec_root "chmod +x /opt/broadcast/broadcast.sh"

    # Fix permissions on db/init-scripts so postgres container (uid 70) can read them
    vm_exec_root "chmod -R o+rX /opt/broadcast/db/init-scripts"

    log_info "Installation prepared."
}

#######################
# Phase 3: Run Installer
#######################

run_installer() {
    log_info "=== Phase 3: Run Installer ==="
    log_info "Running installer..."

    local start_time=$(date +%s)

    if [ "$FLAG_VERBOSE" = true ]; then
        cd "$VAGRANT_DIR" && vagrant ssh -c "sudo bash -c 'cd /opt/broadcast && ./broadcast.sh install'" 2>&1 || {
            local exit_code=$?
            log_fail "Installer exited with code $exit_code"
            return $exit_code
        }
    else
        cd "$VAGRANT_DIR" && vagrant ssh -c "sudo bash -c 'cd /opt/broadcast && ./broadcast.sh install'" >/dev/null 2>&1 || {
            local exit_code=$?
            log_fail "Installer exited with code $exit_code"
            return $exit_code
        }
    fi

    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    log_info "Installation completed in ${elapsed}s."
}

#######################
# Phase 4: Health Checks
#######################

# Retry a check command with polling
wait_for_check() {
    local description="$1"
    local check_cmd="$2"
    local max_retries="${3:-30}"
    local interval="${4:-10}"

    for i in $(seq 1 "$max_retries"); do
        if vm_exec_root "$check_cmd" >/dev/null 2>&1; then
            return 0
        fi
        if [ "$FLAG_VERBOSE" = true ]; then
            echo -e "  ${BLUE}...${NC} retry $i/$max_retries for: $description"
        fi
        sleep "$interval"
    done
    return 1
}

run_health_checks() {
    local phase_label="${1:-Phase 4}"
    log_info "=== $phase_label: Health Checks ==="

    # Check: Docker containers are running
    log_test "Docker containers are running"
    local required_containers=("app" "job" "postgres")
    for container in "${required_containers[@]}"; do
        if wait_for_check "$container container" \
            "docker inspect -f {{.State.Running}} $container 2>/dev/null | grep -q true" 15 10; then
            log_success "Container '$container' is running"
        else
            log_fail "Container '$container' is not running"
        fi
    done

    # Check: PostgreSQL is ready
    log_test "PostgreSQL is accepting connections"
    if wait_for_check "pg_isready" \
        "docker exec postgres pg_isready -U broadcast" 15 10; then
        log_success "PostgreSQL is ready"
    else
        log_fail "PostgreSQL is not accepting connections"
    fi

    # Check: HTTP /up endpoint
    log_test "HTTP /up returns 200"
    if wait_for_check "HTTP /up" \
        "curl -sf http://localhost/up" 30 10; then
        log_success "GET /up returned 200"
    else
        log_fail "GET /up did not return 200"
    fi

    # Check: HTTP /ping endpoint
    log_test "HTTP /ping returns 200"
    if wait_for_check "HTTP /ping" \
        "curl -sf http://localhost/ping" 10 5; then
        log_success "GET /ping returned 200"
    else
        log_fail "GET /ping did not return 200"
    fi

    # Check: systemd service is active
    log_test "broadcast.service is active"
    if vm_exec_root "systemctl is-active broadcast.service" >/dev/null 2>&1; then
        log_success "broadcast.service is active"
    else
        log_fail "broadcast.service is not active"
    fi

    # Check: broadcast user exists
    log_test "broadcast user exists"
    if vm_exec_root "id broadcast" >/dev/null 2>&1; then
        log_success "broadcast user exists"
    else
        log_fail "broadcast user does not exist"
    fi

    # Check: config files exist
    log_test "Config files exist"
    if vm_exec_root "test -f /opt/broadcast/app/.env"; then
        log_success "app/.env exists"
    else
        log_fail "app/.env does not exist"
    fi

    if vm_exec_root "test -f /opt/broadcast/db/.env"; then
        log_success "db/.env exists"
    else
        log_fail "db/.env does not exist"
    fi

    # Check: crontab entries
    log_test "Cron jobs are configured"
    local crontab_content
    crontab_content=$(vm_exec_root "crontab -l 2>/dev/null" || true)
    if echo "$crontab_content" | grep -q "monitor"; then
        log_success "Monitor cron job exists"
    else
        log_fail "Monitor cron job not found"
    fi

    if echo "$crontab_content" | grep -q "trigger"; then
        log_success "Trigger cron job exists"
    else
        log_fail "Trigger cron job not found"
    fi

    # Check: app redirects to onboarding on fresh install
    log_test "Fresh install shows onboarding screen"
    local redirect_location
    redirect_location=$(vm_exec_root "docker exec app curl -sf -o /dev/null -w \"%{redirect_url}\" http://localhost:3000/" 2>/dev/null || true)
    if echo "$redirect_location" | grep -q "onboarding"; then
        log_success "App redirects to onboarding: $redirect_location"
    else
        log_fail "App did not redirect to onboarding (got: $redirect_location)"
    fi
}

#######################
# Inspection: Display key artifacts
#######################

display_inspection() {
    log_info "=== Inspection: System Artifacts ==="
    echo ""

    echo -e "${YELLOW}--- Broadcast Version ---${NC}"
    vm_exec_root "cat /opt/broadcast/.current_version 2>/dev/null || echo 'unknown'" 2>/dev/null
    echo ""

    echo -e "${YELLOW}--- Docker Image (.image) ---${NC}"
    vm_exec_root "cat /opt/broadcast/.image" 2>/dev/null
    echo ""

    echo -e "${YELLOW}--- Docker Containers ---${NC}"
    vm_exec_root "docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'" 2>/dev/null
    echo ""

    echo -e "${YELLOW}--- /opt/broadcast/.env (registry credentials) ---${NC}"
    vm_exec_root "cat /opt/broadcast/.env" 2>/dev/null
    echo ""

    echo -e "${YELLOW}--- /opt/broadcast/app/.env (Rails environment) ---${NC}"
    vm_exec_root "cat /opt/broadcast/app/.env" 2>/dev/null
    echo ""

    echo -e "${YELLOW}--- /opt/broadcast/db/.env (Postgres environment) ---${NC}"
    vm_exec_root "cat /opt/broadcast/db/.env" 2>/dev/null
    echo ""

    echo -e "${YELLOW}--- Crontab ---${NC}"
    vm_exec_root "crontab -l 2>/dev/null" 2>/dev/null
    echo ""

    echo -e "${YELLOW}--- systemctl status broadcast.service ---${NC}"
    vm_exec_root "systemctl status broadcast.service --no-pager -l 2>/dev/null | head -15" 2>/dev/null
    echo ""

    echo -e "${YELLOW}--- Onboarding Redirect ---${NC}"
    vm_exec_root "docker exec app curl -sf -o /dev/null -w \"HTTP %{http_code} -> %{redirect_url}\" http://localhost:3000/ && echo" 2>/dev/null
    echo ""
}

#######################
# Phase 5: Reboot Recovery
#######################

test_reboot_recovery() {
    log_info "=== Phase 5: Reboot Recovery ==="

    log_info "Restarting VM..."
    cd "$VAGRANT_DIR" && vagrant reload

    log_info "VM is back. Re-running health checks..."
    run_health_checks "Phase 5 (post-reboot)"
}

#######################
# Phase 6: Upgrade-path — watcher restart + log streaming survival
#######################

# Exercises the two host-side behaviours that plain install/health checks do not:
#   1. `systemctl restart broadcast-logs-watcher` (what upgrade.sh now runs so a
#      long-running watcher picks up updated scripts) leaves the watcher healthy.
#   2. Log streaming survives container recreation — the actual bug fix. We start
#      streaming via the trigger file, recreate BOTH app and job (so no surviving
#      `docker logs -f` can mask a broken reattach), and assert application.log
#      keeps growing. With the old code the streamer's `wait` returned and the
#      file froze; the supervised reattach loop keeps it live.
#
# This is the fast behavioural check (no real upgrade). For the genuine
# `broadcast.sh upgrade` end-to-end path, see test_real_upgrade / --test-upgrade
# combined with --from-ref.
test_upgrade_and_streaming() {
    log_info "=== Phase 6: Upgrade-path (watcher restart + streaming survival) ==="

    # 1. Watcher restart (the upgrade.sh delivery step) keeps it active + new PID.
    log_test "broadcast-logs-watcher restarts cleanly and stays active"
    local pid_before pid_after
    pid_before=$(vm_exec_root "systemctl show -p MainPID --value broadcast-logs-watcher" | tr -d "[:space:]")
    vm_exec_root "systemctl restart broadcast-logs-watcher || true"
    sleep 3
    pid_after=$(vm_exec_root "systemctl show -p MainPID --value broadcast-logs-watcher" | tr -d "[:space:]")
    if vm_exec_root "systemctl is-active --quiet broadcast-logs-watcher" && [ "$pid_before" != "$pid_after" ]; then
        log_success "watcher restarted (PID ${pid_before} -> ${pid_after}) and is active"
    else
        log_fail "watcher did not restart cleanly (PID ${pid_before} -> ${pid_after})"
    fi

    _test_streaming_lifecycle
}

# Phase 7: genuine end-to-end `broadcast.sh upgrade`. The VM was installed at an
# older ref (--from-ref), so the real upgrade's `git pull` advances the scripts,
# exercising the production path: update -> _upgrade_continue -> watcher restart
# -> container restart. Then we re-verify streaming works on the upgraded host.
test_real_upgrade() {
    log_info "=== Phase 7: Genuine broadcast.sh upgrade ==="

    local head_before head_after
    head_before=$(vm_exec_root "git -C /opt/broadcast rev-parse --short HEAD" | tr -d '[:space:]')
    log_info "Installed (pre-upgrade) script revision: ${head_before}"

    log_test "old watcher is running before upgrade"
    if vm_exec_root "systemctl is-active --quiet broadcast-logs-watcher"; then
        log_success "watcher active pre-upgrade"
    else
        log_fail "watcher not active pre-upgrade"
    fi

    log_test "broadcast.sh upgrade completes (exit 0)"
    if vm_exec_root "cd /opt/broadcast && ./broadcast.sh upgrade"; then
        log_success "broadcast.sh upgrade exited 0"
    else
        log_fail "broadcast.sh upgrade failed"
    fi

    head_after=$(vm_exec_root "git -C /opt/broadcast rev-parse --short HEAD" | tr -d '[:space:]')
    log_test "scripts advanced via the upgrade's git pull"
    if [ -n "$head_after" ] && [ "$head_before" != "$head_after" ]; then
        log_success "scripts upgraded (${head_before} -> ${head_after})"
    else
        log_fail "scripts did not advance (${head_before} -> ${head_after})"
    fi

    log_test "watcher is active after upgrade"
    if wait_for_check "watcher active" "systemctl is-active --quiet broadcast-logs-watcher" 12 5; then
        log_success "watcher active post-upgrade"
    else
        log_fail "watcher not active post-upgrade"
    fi

    # Containers must be healthy again after the upgrade restarted the stack.
    run_health_checks "Phase 7 (post-upgrade)"

    # The fix itself must work end to end on the freshly-upgraded host.
    _test_streaming_lifecycle
}

# Shared streaming lifecycle assertions: start via trigger, survive container
# recreation (reattach), and stop on trigger removal. Used by both the
# behavioural (--test-upgrade) and genuine-upgrade (--test-real-upgrade) phases.
_test_streaming_lifecycle() {
    # Start streaming the way Rails does — by creating the trigger file.
    log_test "creating the trigger starts streaming (application.log populated)"
    vm_exec_root "date -u +%Y-%m-%dT%H:%M:%SZ > /opt/broadcast/app/triggers/logs-stream.txt"
    if wait_for_check "application.log populated" \
        "test -s /opt/broadcast/logs/application.log" 20 3; then
        log_success "application.log is being written"
    else
        log_fail "application.log never populated after trigger created"
    fi

    # The core fix: recreate BOTH containers, streaming must keep flowing (no
    # surviving `docker logs -f` can mask a broken reattach).
    log_test "streaming survives container recreation (docker restart app job)"
    local lines_before
    lines_before=$(vm_exec_root "wc -l < /opt/broadcast/logs/application.log 2>/dev/null" | tr -d "[:space:]")
    vm_exec_root "docker restart app job >/dev/null 2>&1"
    if wait_for_check "application.log grew after restart" \
        "test \$(wc -l < /opt/broadcast/logs/application.log 2>/dev/null) -gt ${lines_before:-0}" 30 5; then
        log_success "application.log kept growing after both containers recreated (reattach works)"
    else
        log_fail "application.log froze after container recreation (reattach failed)"
    fi

    # Removing the trigger stops streaming. First let the app container become
    # exec-ready again after the recreation, otherwise check_log_streaming_trigger's
    # volume guard (docker exec app ...) returns early and defers the stop.
    wait_for_check "app container exec-ready" "docker exec app test -d /rails/logs" 30 5 || true
    log_test "removing the trigger stops streaming"
    vm_exec_root "rm -f /opt/broadcast/app/triggers/logs-stream.txt"
    if wait_for_check "streaming stopped" \
        "! test -f /opt/broadcast/logs/.streaming.pid" 20 3; then
        log_success "streaming stopped after trigger removed"
    else
        log_fail "streaming did not stop after trigger removed"
        log_info "--- diagnostics: watcher log (tail) ---"
        vm_exec_root "tail -n 25 /opt/broadcast/logs/logs-watcher.log 2>/dev/null"
        log_info "--- diagnostics: trigger / pid / streamer state ---"
        vm_exec_root "ls -la /opt/broadcast/app/triggers/ /opt/broadcast/logs/.streaming.pid 2>&1; echo ---; docker ps --format '{{.Names}} {{.Status}}'; echo ---; ps -eo pid,pgid,args | grep -E 'setsid|docker logs' | grep -v grep"
    fi
}

#######################
# Parse CLI Arguments
#######################

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-cleanup)
                FLAG_NO_CLEANUP=true
                ;;
            --test-reboot)
                FLAG_TEST_REBOOT=true
                ;;
            --test-upgrade)
                FLAG_TEST_UPGRADE=true
                ;;
            --test-real-upgrade)
                FLAG_TEST_REAL_UPGRADE=true
                ;;
            --from-ref)
                shift
                if [ $# -eq 0 ]; then
                    echo "Error: --from-ref requires a git ref to install before upgrading"
                    exit 1
                fi
                FROM_REF="$1"
                ;;
            --verbose)
                FLAG_VERBOSE=true
                ;;
            --local)
                FLAG_LOCAL=true
                ;;
            --ubuntu)
                shift
                if [ $# -eq 0 ]; then
                    echo "Error: --ubuntu requires a version (e.g. 24.04, 26.04, or 'all')"
                    exit 1
                fi
                if [ "$1" = "all" ]; then
                    UBUNTU_VERSIONS=("${DEFAULT_UBUNTU_VERSIONS[@]}")
                else
                    UBUNTU_VERSIONS=("$1")
                fi
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --ubuntu VERSION  Ubuntu version to test: 24.04, 26.04, or all (default: all)"
                echo "  --local           Test the local working tree instead of cloning the canonical remote"
                echo "  --no-cleanup      Keep VM after test for debugging"
                echo "  --test-reboot     Also verify services survive a reboot"
                echo "  --test-upgrade    Also verify the log-streaming watcher restart + streaming survives container recreation"
                echo "  --test-real-upgrade  Run a genuine 'broadcast.sh upgrade' (use with --from-ref to install an older rev first)"
                echo "  --from-ref REF    Reset /opt/broadcast to REF before install (remote mode), so an upgrade is genuine old->new"
                echo "  --verbose         Show all command output"
                echo "  --help            Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
        shift
    done
}

#######################
# Main
#######################

run_for_version() {
    local version="$1"

    UBUNTU_VERSION="$version"
    VAGRANT_DIR="$SCRIPT_DIR/.vagrant-smoke-${version}"

    local prev_run=$TESTS_RUN
    local prev_passed=$TESTS_PASSED
    local prev_failed=$TESTS_FAILED

    echo ""
    echo "=========================================="
    echo "  Ubuntu ${version}"
    echo "=========================================="
    echo ""

    setup_vm
    prepare_installation
    run_installer
    run_health_checks "Phase 4 (Ubuntu ${version})"
    display_inspection

    if [ "$FLAG_TEST_REBOOT" = true ]; then
        test_reboot_recovery
    fi

    if [ "$FLAG_TEST_UPGRADE" = true ]; then
        test_upgrade_and_streaming
    fi

    if [ "$FLAG_TEST_REAL_UPGRADE" = true ]; then
        test_real_upgrade
    fi

    # Tear down this version's VM before moving on so disk/VMware resources free up
    cleanup
    VAGRANT_DIR=""

    VERSION_NAMES+=("$version")
    VERSION_RUN+=("$((TESTS_RUN - prev_run))")
    VERSION_PASSED+=("$((TESTS_PASSED - prev_passed))")
    VERSION_FAILED+=("$((TESTS_FAILED - prev_failed))")
}

main() {
    parse_args "$@"

    local repo_source
    if [ "$FLAG_LOCAL" = true ]; then
        repo_source="local working tree"
    else
        repo_source="$BROADCAST_REPO_URL"
    fi

    echo ""
    echo "=========================================="
    echo "  Broadcast Smoke Test (Vagrant)"
    echo "  Ubuntu versions: ${UBUNTU_VERSIONS[*]}"
    echo "  Repo source:     ${repo_source}"
    echo "=========================================="
    echo ""

    trap cleanup EXIT

    load_credentials

    for version in "${UBUNTU_VERSIONS[@]}"; do
        run_for_version "$version"
    done

    # Summary
    echo ""
    echo "=========================================="
    echo "  Test Summary"
    echo "=========================================="
    echo ""
    for i in "${!VERSION_NAMES[@]}"; do
        local name="${VERSION_NAMES[$i]}"
        local run="${VERSION_RUN[$i]}"
        local passed="${VERSION_PASSED[$i]}"
        local failed="${VERSION_FAILED[$i]}"
        if [ "$failed" -eq 0 ]; then
            echo -e "  Ubuntu ${name}: ${GREEN}${passed}/${run} passed${NC}"
        else
            echo -e "  Ubuntu ${name}: ${RED}${failed} failed${NC} (${passed}/${run} passed)"
        fi
    done
    echo ""
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

main "$@"
