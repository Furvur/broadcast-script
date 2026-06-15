#!/bin/bash

# Unit tests for on-demand log streaming control flow (scripts/logs.sh).
#
# These cover the regression that left log streaming dead for months: the
# streamer dying on container recreation and never restarting. We exercise the
# control flow - the idempotency guard, the PID/trigger/output file lifecycle,
# and trigger->streamer reconciliation - by mocking the external commands
# (docker, setsid, ps, pkill) and isolating all paths under TEST_TMP_DIR.
#
# Scope: the real `docker logs` re-attach loop and process-group kill are NOT
# exercised here (setsid/docker are mocked); those are validated by host
# verification. See tests/README.md / the plan for details.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../test_framework.sh"
source "$PROJECT_ROOT/scripts/logs.sh"

# Invoke a function-under-test the way production does. logs.sh is sourced by
# the watcher with `set -e` OFF, so its intentionally-suppressed `kill`/`pkill`
# failures are no-ops there; the test framework runs with `set -e` ON, which
# would otherwise abort mid-function. Always call this in a checked context
# (if / || true) so the wrapper's own non-zero return doesn't trip `set -e`.
run_sut() {
    set +e
    "$@"
    local rc=$?
    set -e
    return $rc
}

# Per-test isolation: point the streaming paths at TEST_TMP_DIR, clear state,
# and reset mocks so every test declares exactly the externals it needs.
setup_logs_test() {
    LOGS_TRIGGER="$TEST_TMP_DIR/triggers/logs-stream.txt"
    LOGS_OUTPUT="$TEST_TMP_DIR/logs/application.log"
    LOGS_PID_FILE="$TEST_TMP_DIR/logs/.streaming.pid"

    mkdir -p "$TEST_TMP_DIR/triggers" "$TEST_TMP_DIR/logs"
    rm -f "$LOGS_TRIGGER" "$LOGS_OUTPUT" "$LOGS_PID_FILE"

    rm -f "$TEST_TMP_DIR"/mocks/* 2>/dev/null || true
    : > "$TEST_TMP_DIR/mocked_commands"
}

# --- is_streaming_active -----------------------------------------------------

test_is_streaming_active_false_without_pid_file() {
    assert_file_not_exists "$LOGS_PID_FILE" "Precondition: no PID file"

    if run_sut is_streaming_active; then
        assert_equals "inactive" "active" "Should report inactive with no PID file"
    fi
}

test_is_streaming_active_cleans_stale_pid_file() {
    # A PID that is not running (use an almost-certainly-dead PID).
    echo "999999" > "$LOGS_PID_FILE"

    if run_sut is_streaming_active; then
        assert_equals "inactive" "active" "Dead PID should report inactive"
    fi
    assert_file_not_exists "$LOGS_PID_FILE" "Stale PID file should be cleaned up"
}

test_is_streaming_active_true_for_live_streamer() {
    sleep 100 &
    local live_pid=$!
    echo "$live_pid" > "$LOGS_PID_FILE"
    # is_streaming_active confirms the process is one of ours via its args.
    mock_command "ps" "docker logs -f --timestamps app" 0

    if run_sut is_streaming_active; then
        assert_equals "active" "active" "Live streamer should report active"
    else
        assert_equals "active" "inactive" "Live streamer should report active"
    fi

    kill "$live_pid" 2>/dev/null || true
}

# --- start_log_streaming -----------------------------------------------------

test_start_log_streaming_creates_pid_and_output() {
    mock_command "setsid" "" 0

    run_sut start_log_streaming || true

    assert_file_exists "$LOGS_PID_FILE" "start should write the PID file"
    assert_file_exists "$LOGS_OUTPUT" "start should (re)create the output file"
}

test_start_log_streaming_is_idempotent_when_active() {
    sleep 100 &
    local live_pid=$!
    echo "$live_pid" > "$LOGS_PID_FILE"
    mock_command "ps" "docker logs -f --timestamps app" 0
    mock_command "setsid" "" 0

    local before after
    before=$(cat "$LOGS_PID_FILE")
    run_sut start_log_streaming || true
    after=$(cat "$LOGS_PID_FILE")

    assert_equals "$before" "$after" "start must not relaunch over a live streamer"

    kill "$live_pid" 2>/dev/null || true
}

# --- stop_log_streaming ------------------------------------------------------

test_stop_log_streaming_removes_pid_and_output() {
    echo "999999" > "$LOGS_PID_FILE"
    echo "old log line" > "$LOGS_OUTPUT"
    mock_command "ps" "99999" 0   # pgid lookup -> harmless non-existent group
    mock_command "pkill" "" 0

    run_sut stop_log_streaming || true

    assert_file_not_exists "$LOGS_PID_FILE" "stop should remove the PID file"
    assert_file_not_exists "$LOGS_OUTPUT" "stop should remove the stale output file"
}

# --- check_log_streaming_trigger ---------------------------------------------

test_reconcile_starts_when_trigger_present() {
    echo "2026-01-01T00:00:00Z" > "$LOGS_TRIGGER"
    mock_command "docker" "" 0    # `docker exec app test -d /rails/logs` succeeds
    mock_command "setsid" "" 0

    run_sut check_log_streaming_trigger || true

    assert_file_exists "$LOGS_PID_FILE" "Trigger present + volume mounted should start streaming"
}

test_reconcile_stops_when_trigger_absent() {
    sleep 100 &
    local live_pid=$!
    echo "$live_pid" > "$LOGS_PID_FILE"
    rm -f "$LOGS_TRIGGER"
    mock_command "docker" "" 0    # volume check passes
    mock_command "ps" "docker logs -f --timestamps app" 0
    mock_command "pkill" "" 0

    run_sut check_log_streaming_trigger || true

    assert_file_not_exists "$LOGS_PID_FILE" "No trigger + active streamer should stop streaming"

    kill "$live_pid" 2>/dev/null || true
}

test_reconcile_clears_trigger_when_volume_unmounted() {
    echo "2026-01-01T00:00:00Z" > "$LOGS_TRIGGER"
    mock_command "docker" "" 1    # `docker exec ... test -d /rails/logs` fails

    run_sut check_log_streaming_trigger || true

    assert_file_not_exists "$LOGS_TRIGGER" "Stale trigger should be cleared when volume is not mounted"
    assert_file_not_exists "$LOGS_PID_FILE" "No streamer should start when volume is not mounted"
}

# --- runner ------------------------------------------------------------------

run_log_streaming_tests() {
    echo "Running Log Streaming Tests"
    echo "==========================="

    init_test_framework

    TEST_SETUP_FUNCTION="setup_logs_test"

    run_test "test_is_streaming_active_false_without_pid_file" test_is_streaming_active_false_without_pid_file
    run_test "test_is_streaming_active_cleans_stale_pid_file" test_is_streaming_active_cleans_stale_pid_file
    run_test "test_is_streaming_active_true_for_live_streamer" test_is_streaming_active_true_for_live_streamer
    run_test "test_start_log_streaming_creates_pid_and_output" test_start_log_streaming_creates_pid_and_output
    run_test "test_start_log_streaming_is_idempotent_when_active" test_start_log_streaming_is_idempotent_when_active
    run_test "test_stop_log_streaming_removes_pid_and_output" test_stop_log_streaming_removes_pid_and_output
    run_test "test_reconcile_starts_when_trigger_present" test_reconcile_starts_when_trigger_present
    run_test "test_reconcile_stops_when_trigger_absent" test_reconcile_stops_when_trigger_absent
    run_test "test_reconcile_clears_trigger_when_volume_unmounted" test_reconcile_clears_trigger_when_volume_unmounted

    local result
    print_test_summary
    result=$?

    cleanup_test_framework
    return $result
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_log_streaming_tests
fi
