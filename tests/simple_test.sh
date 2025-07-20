#!/bin/bash

# Simple test to verify the framework works

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_framework.sh"

test_basic_assertions() {
    assert_equals "hello" "hello" "String equality test"
    assert_contains "hello world" "world" "String contains test"
    
    # Test file operations with temp files
    local test_file="$TEST_TMP_DIR/test.txt"
    echo "test content" > "$test_file"
    assert_file_exists "$test_file" "File should exist"
    
    local content=$(cat "$test_file")
    assert_equals "test content" "$content" "File content should match"
}

test_command_mocking() {
    # Mock a command (use a command that's not a shell builtin)
    mock_command "curl" "mocked curl output" 0
    
    # Test the mocked command
    local output=$(curl "anything")
    assert_equals "mocked curl output" "$output" "Should return mocked output"
}

test_exit_codes() {
    # Create a script that exits with code 1
    local test_script="$TEST_TMP_DIR/fail_script.sh"
    echo '#!/bin/bash' > "$test_script"
    echo 'exit 1' >> "$test_script"
    chmod +x "$test_script"
    
    assert_exit_code 1 "$test_script" "Script should exit with code 1"
}

run_simple_tests() {
    echo "Running Simple Framework Tests"
    echo "=============================="
    
    init_test_framework
    
    run_test "test_basic_assertions" test_basic_assertions
    run_test "test_command_mocking" test_command_mocking  
    run_test "test_exit_codes" test_exit_codes
    
    local result
    print_test_summary
    result=$?
    
    cleanup_test_framework
    return $result
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_simple_tests
fi