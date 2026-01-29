#!/bin/bash

# Docker-based integration test for backup/restore functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
TEST_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="/tmp/broadcast-backup-test"

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

cleanup() {
    log_info "Cleaning up..."
    docker compose -f "$TEST_DIR/docker-compose.test.yml" down -v 2>/dev/null || true
    rm -rf "$BACKUP_DIR"
}

wait_for_postgres() {
    log_info "Waiting for PostgreSQL to be ready..."
    for i in {1..30}; do
        if docker compose -f "$TEST_DIR/docker-compose.test.yml" exec -T postgres pg_isready -U broadcast > /dev/null 2>&1; then
            log_info "PostgreSQL is ready"
            return 0
        fi
        sleep 1
    done
    log_fail "PostgreSQL failed to start"
    exit 1
}

get_row_count() {
    local table=$1
    docker compose -f "$TEST_DIR/docker-compose.test.yml" exec -T postgres \
        psql -U broadcast -d broadcast_primary_production -t -c "SELECT COUNT(*) FROM $table;" | tr -d ' '
}

#######################
# Source backup/restore functions
#######################

# Compare two semantic versions. Returns:
#   0 if equal
#   1 if first > second
#   2 if first < second
compare_versions() {
    if [ "$1" = "$2" ]; then
        return 0
    fi

    local IFS=.
    local i ver1=($1) ver2=($2)

    # Fill empty positions with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    for ((i=${#ver2[@]}; i<${#ver1[@]}; i++)); do
        ver2[i]=0
    done

    for ((i=0; i<${#ver1[@]}; i++)); do
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2
        fi
    done
    return 0
}

#######################
# Test Functions
#######################

test_version_comparison() {
    log_test "Version comparison function"
    local result

    # Test equal versions
    compare_versions "1.0.0" "1.0.0" && result=0 || result=$?
    if [ $result -eq 0 ]; then
        log_success "1.0.0 == 1.0.0"
    else
        log_fail "1.0.0 == 1.0.0 (expected equal)"
    fi

    # Test first > second
    compare_versions "2.0.0" "1.0.0" && result=0 || result=$?
    if [ $result -eq 1 ]; then
        log_success "2.0.0 > 1.0.0"
    else
        log_fail "2.0.0 > 1.0.0 (expected first greater)"
    fi

    # Test first < second
    compare_versions "1.0.0" "2.0.0" && result=0 || result=$?
    if [ $result -eq 2 ]; then
        log_success "1.0.0 < 2.0.0"
    else
        log_fail "1.0.0 < 2.0.0 (expected first less)"
    fi

    # Test minor version
    compare_versions "1.2.0" "1.1.0" && result=0 || result=$?
    if [ $result -eq 1 ]; then
        log_success "1.2.0 > 1.1.0"
    else
        log_fail "1.2.0 > 1.1.0 (expected first greater)"
    fi

    # Test patch version
    compare_versions "1.0.1" "1.0.2" && result=0 || result=$?
    if [ $result -eq 2 ]; then
        log_success "1.0.1 < 1.0.2"
    else
        log_fail "1.0.1 < 1.0.2 (expected first less)"
    fi
}

test_backup_creation() {
    log_test "Backup creation and archive structure"

    mkdir -p "$BACKUP_DIR"

    # Create backup using pg_dump
    local timestamp=$(date +%Y-%m-%d-%H-%M-%S)
    local version="1.0.0"
    local backup_name="broadcast-backup-v${version}-${timestamp}"

    log_info "Creating database dump..."
    docker compose -f "$TEST_DIR/docker-compose.test.yml" exec -T postgres \
        pg_dump -U broadcast -Fc broadcast_primary_production > "$BACKUP_DIR/${backup_name}.dump"

    # Create VERSION file
    echo "$version" > "$BACKUP_DIR/VERSION"

    # Create archive
    log_info "Creating backup archive..."
    tar -czf "$BACKUP_DIR/${backup_name}.tar.gz" -C "$BACKUP_DIR" "${backup_name}.dump" VERSION

    # Verify archive structure
    local archive_contents=$(tar -tzf "$BACKUP_DIR/${backup_name}.tar.gz")

    if echo "$archive_contents" | grep -q ".dump"; then
        log_success "Archive contains .dump file"
    else
        log_fail "Archive missing .dump file"
    fi

    if echo "$archive_contents" | grep -q "VERSION"; then
        log_success "Archive contains VERSION file"
    else
        log_fail "Archive missing VERSION file"
    fi

    # Store for later tests
    BACKUP_ARCHIVE="$BACKUP_DIR/${backup_name}.tar.gz"
    BACKUP_VERSION="$version"
}

test_backup_extraction() {
    log_test "Backup extraction and file discovery"

    local extract_dir="$BACKUP_DIR/extract-test"
    mkdir -p "$extract_dir"

    # Extract archive
    tar -xzf "$BACKUP_ARCHIVE" -C "$extract_dir"

    # Find VERSION file
    if [ -f "$extract_dir/VERSION" ]; then
        local extracted_version=$(cat "$extract_dir/VERSION")
        if [ "$extracted_version" = "$BACKUP_VERSION" ]; then
            log_success "VERSION file extracted correctly: $extracted_version"
        else
            log_fail "VERSION mismatch: expected $BACKUP_VERSION, got $extracted_version"
        fi
    else
        log_fail "VERSION file not found after extraction"
    fi

    # Find dump file
    local dump_file=$(find "$extract_dir" -name "*.dump" -type f | head -1)
    if [ -n "$dump_file" ]; then
        log_success "Dump file found: $(basename "$dump_file")"
        DUMP_FILE="$dump_file"
    else
        log_fail "Dump file not found after extraction"
    fi
}

test_restore_data_integrity() {
    log_test "Restore and data integrity verification"

    # Get row counts before clearing
    local channels_before=$(get_row_count "broadcast_channels")
    local subscribers_before=$(get_row_count "subscribers")
    local broadcasts_before=$(get_row_count "broadcasts")

    log_info "Row counts before restore:"
    log_info "  broadcast_channels: $channels_before"
    log_info "  subscribers: $subscribers_before"
    log_info "  broadcasts: $broadcasts_before"

    # Drop and recreate database to simulate fresh install
    log_info "Dropping and recreating database..."
    docker compose -f "$TEST_DIR/docker-compose.test.yml" exec -T postgres \
        psql -U broadcast -d postgres -c "DROP DATABASE IF EXISTS broadcast_primary_production;"
    docker compose -f "$TEST_DIR/docker-compose.test.yml" exec -T postgres \
        psql -U broadcast -d postgres -c "CREATE DATABASE broadcast_primary_production OWNER broadcast;"

    # Verify database is empty
    local tables_after_drop=$(docker compose -f "$TEST_DIR/docker-compose.test.yml" exec -T postgres \
        psql -U broadcast -d broadcast_primary_production -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | tr -d ' ')

    if [ "$tables_after_drop" = "0" ]; then
        log_success "Database cleared successfully"
    else
        log_fail "Database not cleared properly"
    fi

    # Restore from backup
    log_info "Restoring from backup..."
    docker cp "$DUMP_FILE" broadcast-postgres-test:/tmp/restore.dump

    docker compose -f "$TEST_DIR/docker-compose.test.yml" exec -T postgres \
        pg_restore -U broadcast -d broadcast_primary_production \
        --clean --if-exists --no-owner --no-privileges \
        /tmp/restore.dump 2>/dev/null || true  # pg_restore returns non-zero for warnings

    # Verify row counts after restore
    local channels_after=$(get_row_count "broadcast_channels")
    local subscribers_after=$(get_row_count "subscribers")
    local broadcasts_after=$(get_row_count "broadcasts")

    log_info "Row counts after restore:"
    log_info "  broadcast_channels: $channels_after"
    log_info "  subscribers: $subscribers_after"
    log_info "  broadcasts: $broadcasts_after"

    # Compare counts
    if [ "$channels_before" = "$channels_after" ]; then
        log_success "broadcast_channels: $channels_before rows restored correctly"
    else
        log_fail "broadcast_channels: expected $channels_before, got $channels_after"
    fi

    if [ "$subscribers_before" = "$subscribers_after" ]; then
        log_success "subscribers: $subscribers_before rows restored correctly"
    else
        log_fail "subscribers: expected $subscribers_before, got $subscribers_after"
    fi

    if [ "$broadcasts_before" = "$broadcasts_after" ]; then
        log_success "broadcasts: $broadcasts_before rows restored correctly"
    else
        log_fail "broadcasts: expected $broadcasts_before, got $broadcasts_after"
    fi
}

test_version_mismatch_detection() {
    log_test "Version mismatch detection (newer backup → older install)"

    # Simulate: backup is v2.0.0, installed is v1.0.0
    local backup_version="2.0.0"
    local installed_version="1.0.0"
    local result

    compare_versions "$backup_version" "$installed_version" && result=0 || result=$?

    if [ $result -eq 1 ]; then
        log_success "Correctly detected newer backup ($backup_version) than installation ($installed_version)"
    else
        log_fail "Failed to detect version mismatch"
    fi
}

test_older_backup_allowed() {
    log_test "Older backup to newer install (should be allowed)"

    # Simulate: backup is v1.0.0, installed is v2.0.0
    local backup_version="1.0.0"
    local installed_version="2.0.0"
    local result

    compare_versions "$backup_version" "$installed_version" && result=0 || result=$?

    if [ $result -eq 2 ]; then
        log_success "Correctly identified older backup ($backup_version) than installation ($installed_version) - migrations would run"
    else
        log_fail "Failed to identify older backup scenario"
    fi
}

#######################
# Main Test Runner
#######################

main() {
    echo ""
    echo "=========================================="
    echo "  Backup/Restore Integration Tests"
    echo "=========================================="
    echo ""

    trap cleanup EXIT

    # Start PostgreSQL
    log_info "Starting PostgreSQL container..."
    docker compose -f "$TEST_DIR/docker-compose.test.yml" up -d
    wait_for_postgres

    # Give seed data time to load
    sleep 2

    # Run tests
    test_version_comparison
    test_backup_creation
    test_backup_extraction
    test_restore_data_integrity
    test_version_mismatch_detection
    test_older_backup_allowed

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
