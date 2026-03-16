#!/bin/bash

# Smoke Test for Broadcast Installation
#
# Spins up a disposable Ubuntu 24.04 VM, runs the real installer,
# and verifies the system boots successfully.
#
# Usage:
#   ./tests/smoke/test_multipass_smoke.sh                 # Basic smoke test
#   ./tests/smoke/test_multipass_smoke.sh --no-cleanup    # Keep VM for debugging
#   ./tests/smoke/test_multipass_smoke.sh --test-reboot   # Verify reboot recovery
#   ./tests/smoke/test_multipass_smoke.sh --verbose       # Show all command output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
VAGRANT_DIR="$SCRIPT_DIR/.vagrant-smoke"

# CLI flags
FLAG_NO_CLEANUP=false
FLAG_TEST_REBOOT=false
FLAG_VERBOSE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

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
    if [ "$FLAG_NO_CLEANUP" = true ]; then
        log_warn "Skipping cleanup (--no-cleanup). VM is still running in $VAGRANT_DIR"
        log_warn "To clean up manually: cd $VAGRANT_DIR && vagrant destroy -f"
        return
    fi

    log_info "Cleaning up VM..."
    cd "$VAGRANT_DIR" && vagrant destroy -f 2>/dev/null || true
    rm -rf "$VAGRANT_DIR"
}

#######################
# Phase 1: Setup VM
#######################

setup_vm() {
    log_info "=== Phase 1: Setup VM ==="

    # Check vagrant is installed
    if ! command -v vagrant &>/dev/null; then
        echo -e "${RED}Error: Vagrant is not installed.${NC}"
        echo "Install it with: brew install vagrant"
        exit 1
    fi

    # Create Vagrant working directory
    mkdir -p "$VAGRANT_DIR"

    # Generate Vagrantfile
    cat > "$VAGRANT_DIR/Vagrantfile" <<'VAGRANTEOF'
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.hostname = "broadcast-smoke-test"

  config.vm.provider "vmware_desktop" do |v|
    v.vmx["numvcpus"] = "2"
    v.vmx["memsize"] = "2048"
  end

  config.vm.provider "virtualbox" do |v|
    v.memory = 2048
    v.cpus = 2
  end

  # Share repo to a temp location, then copy to /opt/broadcast in provisioning
  config.vm.synced_folder "BROADCAST_REPO_PATH", "/tmp/broadcast-repo"

  config.vm.provision "shell", inline: <<-SHELL
    mkdir -p /opt/broadcast
    cp -a /tmp/broadcast-repo/. /opt/broadcast/
  SHELL
end
VAGRANTEOF

    # Replace placeholder with actual repo path
    sed -i '' "s|BROADCAST_REPO_PATH|${PROJECT_ROOT}|" "$VAGRANT_DIR/Vagrantfile"

    # Launch VM
    log_info "Launching Ubuntu 24.04 VM..."
    cd "$VAGRANT_DIR" && vagrant up

    log_info "VM is ready."
}

#######################
# Phase 2: Prepare Installation
#######################

prepare_installation() {
    log_info "=== Phase 2: Prepare Installation ==="

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
            --verbose)
                FLAG_VERBOSE=true
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --no-cleanup    Keep VM after test for debugging"
                echo "  --test-reboot   Also verify services survive a reboot"
                echo "  --verbose       Show all command output"
                echo "  --help          Show this help message"
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

main() {
    parse_args "$@"

    echo ""
    echo "=========================================="
    echo "  Broadcast Smoke Test (Vagrant)"
    echo "=========================================="
    echo ""

    trap cleanup EXIT

    load_credentials
    setup_vm
    prepare_installation
    run_installer
    run_health_checks "Phase 4"
    display_inspection

    if [ "$FLAG_TEST_REBOOT" = true ]; then
        test_reboot_recovery
    fi

    # Summary
    echo ""
    echo "=========================================="
    echo "  Test Summary"
    echo "=========================================="
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
