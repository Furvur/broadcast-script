#!/bin/bash

# Unit tests for the real systemd service management scripts:
#   - create_broadcast_service (scripts/init-services.sh): generated unit
#     file content and the disable/reload/enable sequence
#   - scripts/post-upgrade-cleanup.sh: the container stability gate that
#     decides whether `docker image prune -af` may run
#
# post-upgrade-cleanup.sh is a standalone script (not a sourced function),
# so it runs unmodified via bash with the sandbox mocks first on PATH.
# Its GNU `date -d` usage is shimmed with fixed epochs (macOS date lacks -d).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../test_framework.sh"
source "$SCRIPT_DIR/../script_harness.sh"

UNIT_FILE=""

setup_sandbox() {
    harness_make_sandbox
    UNIT_FILE="$SANDBOX_ROOT/etc/systemd/system/broadcast.service"
}

teardown_sandbox() {
    harness_destroy_sandbox
}

# --- create_broadcast_service --------------------------------------------

test_create_service_writes_correct_unit_file() {
    local rc=0
    sandbox_run "create_broadcast_service" >/dev/null || rc=$?
    assert_equals "0" "$rc" "create_broadcast_service should succeed"

    assert_file_exists "$UNIT_FILE" "the unit file should be written"

    local unit
    unit=$(cat "$UNIT_FILE")
    assert_contains "$unit" "Requires=docker.service" "service must require docker"
    assert_contains "$unit" "After=docker.service" "service must start after docker"
    assert_contains "$unit" "User=broadcast" "service must run as the broadcast user"
    assert_contains "$unit" "Restart=always" "service must auto-restart"
    assert_contains "$unit" "WantedBy=multi-user.target" "service must be installable for boot"
    assert_contains "$unit" "docker compose -f" "start/stop must go through docker compose"
    assert_contains "$unit" ".image" "the image env file must be loaded before compose"
}

test_create_service_reloads_and_enables() {
    sandbox_run "create_broadcast_service" >/dev/null

    harness_assert_call_order \
        "systemctl daemon-reload" \
        "systemctl enable broadcast.service"
}

test_create_service_disables_an_active_service_first() {
    # Default systemctl mock reports is-active as success
    sandbox_run "create_broadcast_service" >/dev/null

    harness_assert_call_order \
        "systemctl disable broadcast.service" \
        "systemctl daemon-reload"
}

test_create_service_skips_disable_when_not_active() {
    harness_mock systemctl 'if [ "${1:-}" = "is-active" ]; then exit 1; fi
exit 0'
    sandbox_run "create_broadcast_service" >/dev/null

    harness_assert_not_called "systemctl disable" \
        "an inactive service must not be disabled"
    harness_assert_called "systemctl enable broadcast.service" \
        "the service should still be enabled"
}

# --- post-upgrade-cleanup.sh ----------------------------------------------

# Run the unmodified cleanup script with the sandbox mocks first on PATH.
# DOCKER_MOCK_DOWN_CONTAINER marks one container as not running;
# DATE_MOCK_*_EPOCH control the computed container uptime.
run_cleanup_script() {
    harness_mock docker 'case "$*" in
  *"{{.State.Status}}"*)
    if [ "${!#}" = "${DOCKER_MOCK_DOWN_CONTAINER:-}" ]; then echo "exited"; else echo "running"; fi ;;
  *"{{.State.StartedAt}}"*) echo "2026-01-01T00:00:00Z" ;;
esac
exit 0'
    harness_mock date 'case "$*" in
  *"-d"*) echo "${DATE_MOCK_STARTED_EPOCH:-1000}" ;;
  "+%s") echo "${DATE_MOCK_NOW_EPOCH:-2000}" ;;
  *) echo "2026-01-01 00:00:00 UTC" ;;
esac'

    PATH="$SANDBOX_ROOT/mocks:$PATH" bash "$HARNESS_PROJECT_ROOT/scripts/post-upgrade-cleanup.sh" 2>&1
}

test_cleanup_prunes_when_all_containers_are_stable() {
    local output
    output=$(run_cleanup_script)

    assert_contains "$output" "All containers stable" "stability should be confirmed"
    harness_assert_called "docker image prune -af" "stable containers allow the prune"
}

test_cleanup_skips_when_a_container_is_not_running() {
    local output
    output=$(DOCKER_MOCK_DOWN_CONTAINER=job run_cleanup_script)

    assert_contains "$output" "'job' is not running" "the down container should be named"
    assert_contains "$output" "Skipping cleanup" "cleanup must be skipped"
    harness_assert_not_called "docker image prune" \
        "prune must not run while a container is down"
}

test_cleanup_skips_when_a_container_restarted_too_recently() {
    # Uptime of 30s is under the 60s stability threshold
    local output
    output=$(DATE_MOCK_STARTED_EPOCH=1000 DATE_MOCK_NOW_EPOCH=1030 run_cleanup_script)

    assert_contains "$output" "need 60s" "the unmet threshold should be reported"
    harness_assert_not_called "docker image prune" \
        "prune must not run for a freshly restarted container"
}

run_system_service_tests() {
    echo "Running System Service Script Tests"
    echo "==================================="

    init_test_framework

    TEST_SETUP_FUNCTION="setup_sandbox"
    TEST_TEARDOWN_FUNCTION="teardown_sandbox"

    run_test "test_create_service_writes_correct_unit_file" test_create_service_writes_correct_unit_file
    run_test "test_create_service_reloads_and_enables" test_create_service_reloads_and_enables
    run_test "test_create_service_disables_an_active_service_first" test_create_service_disables_an_active_service_first
    run_test "test_create_service_skips_disable_when_not_active" test_create_service_skips_disable_when_not_active
    run_test "test_cleanup_prunes_when_all_containers_are_stable" test_cleanup_prunes_when_all_containers_are_stable
    run_test "test_cleanup_skips_when_a_container_is_not_running" test_cleanup_skips_when_a_container_is_not_running
    run_test "test_cleanup_skips_when_a_container_restarted_too_recently" test_cleanup_skips_when_a_container_restarted_too_recently

    local result
    print_test_summary
    result=$?

    cleanup_test_framework
    return $result
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_system_service_tests
fi
