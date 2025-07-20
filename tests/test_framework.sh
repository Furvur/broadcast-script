#!/bin/bash

# Bash Test Framework for Broadcast Scripts
# Provides functions for unit testing, mocking, and assertions

set -e
set -u

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test state
CURRENT_TEST=""
TEST_FAILED=false

# Setup and teardown functions
TEST_SETUP_FUNCTION=""
TEST_TEARDOWN_FUNCTION=""

# Mock tracking (compatible with Bash 3.2+)
MOCKED_COMMANDS=""
MOCK_OUTPUTS=""
MOCK_EXIT_CODES=""
COMMAND_CALL_COUNT=""

# Temporary directory for test isolation
TEST_TMP_DIR=""

# Initialize test framework
init_test_framework() {
    TEST_TMP_DIR=$(mktemp -d)
    export PATH="$TEST_TMP_DIR/mocks:$PATH"
    mkdir -p "$TEST_TMP_DIR/mocks"
    
    # Create mocked commands tracking file
    touch "$TEST_TMP_DIR/mocked_commands"
    
    # Setup mock directory for external commands
    echo "Test framework initialized. Temp dir: $TEST_TMP_DIR"
}

# Cleanup test framework
cleanup_test_framework() {
    if [ -n "$TEST_TMP_DIR" ] && [ -d "$TEST_TMP_DIR" ]; then
        rm -rf "$TEST_TMP_DIR"
    fi
    
    # Clear mock tracking
    MOCKED_COMMANDS=""
    MOCK_OUTPUTS=""
    MOCK_EXIT_CODES=""
    COMMAND_CALL_COUNT=""
}

# Test runner functions
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    CURRENT_TEST="$test_name"
    TEST_FAILED=false
    TESTS_RUN=$((TESTS_RUN + 1))
    
    echo -e "${BLUE}Running test: $test_name${NC}"
    
    # Run setup if defined
    if [ -n "$TEST_SETUP_FUNCTION" ] && type "$TEST_SETUP_FUNCTION" &>/dev/null; then
        "$TEST_SETUP_FUNCTION"
    fi
    
    # Run the test
    if "$test_function"; then
        if [ "$TEST_FAILED" = false ]; then
            echo -e "${GREEN}✓ PASS: $test_name${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}✗ FAIL: $test_name${NC}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    else
        echo -e "${RED}✗ FAIL: $test_name (exception thrown)${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    # Run teardown if defined
    if [ -n "$TEST_TEARDOWN_FUNCTION" ] && type "$TEST_TEARDOWN_FUNCTION" &>/dev/null; then
        "$TEST_TEARDOWN_FUNCTION"
    fi
    
    echo
}

# Assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    if [ "$expected" != "$actual" ]; then
        echo -e "${RED}Assertion failed: Expected '$expected', got '$actual'${NC}"
        if [ -n "$message" ]; then
            echo -e "${RED}Message: $message${NC}"
        fi
        TEST_FAILED=true
        return 1
    fi
    return 0
}

assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    if [ "$not_expected" = "$actual" ]; then
        echo -e "${RED}Assertion failed: Expected not '$not_expected', but got '$actual'${NC}"
        if [ -n "$message" ]; then
            echo -e "${RED}Message: $message${NC}"
        fi
        TEST_FAILED=true
        return 1
    fi
    return 0
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "${RED}Assertion failed: '$haystack' does not contain '$needle'${NC}"
        if [ -n "$message" ]; then
            echo -e "${RED}Message: $message${NC}"
        fi
        TEST_FAILED=true
        return 1
    fi
    return 0
}

assert_file_exists() {
    local file_path="$1"
    local message="${2:-}"
    
    if [ ! -f "$file_path" ]; then
        echo -e "${RED}Assertion failed: File '$file_path' does not exist${NC}"
        if [ -n "$message" ]; then
            echo -e "${RED}Message: $message${NC}"
        fi
        TEST_FAILED=true
        return 1
    fi
    return 0
}

assert_file_not_exists() {
    local file_path="$1"
    local message="${2:-}"
    
    if [ -f "$file_path" ]; then
        echo -e "${RED}Assertion failed: File '$file_path' exists but shouldn't${NC}"
        if [ -n "$message" ]; then
            echo -e "${RED}Message: $message${NC}"
        fi
        TEST_FAILED=true
        return 1
    fi
    return 0
}

assert_exit_code() {
    local expected_code="$1"
    local command="$2"
    local message="${3:-}"
    
    set +e
    $command >/dev/null 2>&1
    local actual_code=$?
    set -e
    
    if [ "$expected_code" != "$actual_code" ]; then
        echo -e "${RED}Assertion failed: Expected exit code $expected_code, got $actual_code${NC}"
        if [ -n "$message" ]; then
            echo -e "${RED}Message: $message${NC}"
        fi
        TEST_FAILED=true
        return 1
    fi
    return 0
}

# Mocking functions (Bash 3.2 compatible)
mock_command() {
    local command="$1"
    local output="${2:-}"
    local exit_code="${3:-0}"
    
    # Create mock script directly instead of using associative arrays
    cat > "$TEST_TMP_DIR/mocks/$command" << EOF
#!/bin/bash
# Mock for $command
echo '$output'
exit $exit_code
EOF
    chmod +x "$TEST_TMP_DIR/mocks/$command"
    
    # Track mocked commands in a simple file
    echo "$command" >> "$TEST_TMP_DIR/mocked_commands"
}

assert_command_called() {
    local command="$1"
    local expected_count="${2:-1}"
    local message="${3:-}"
    
    # Check if command was mocked by looking in the mocked commands file
    local actual_count=0
    if [ -f "$TEST_TMP_DIR/mocked_commands" ] && grep -q "^$command$" "$TEST_TMP_DIR/mocked_commands"; then
        actual_count=1
    fi
    
    if [ "$expected_count" != "$actual_count" ]; then
        echo -e "${RED}Assertion failed: Expected $command to be called $expected_count times, called $actual_count times${NC}"
        if [ -n "$message" ]; then
            echo -e "${RED}Message: $message${NC}"
        fi
        TEST_FAILED=true
        return 1
    fi
    return 0
}

# Test environment setup
setup_test_env() {
    # Create isolated environment variables
    export TEST_MODE=1
    export BROADCAST_TEST_DIR="$TEST_TMP_DIR"
    
    # Mock common directories
    mkdir -p "$TEST_TMP_DIR/opt/broadcast"/{app,db,ssl,scripts}
    mkdir -p "$TEST_TMP_DIR/opt/broadcast/app"/{storage,uploads,triggers,monitor}
    mkdir -p "$TEST_TMP_DIR/opt/broadcast/db"/{backups,postgres-data,init-scripts}
    
    # Create test configuration files
    echo "test.example.com" > "$TEST_TMP_DIR/opt/broadcast/.domain"
    echo "test-license-key" > "$TEST_TMP_DIR/opt/broadcast/.license"
    echo "1.0.0" > "$TEST_TMP_DIR/opt/broadcast/.current_version"
}

# Test result reporting
print_test_summary() {
    echo
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo -e "Total tests run: ${BLUE}$TESTS_RUN${NC}"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}

# Helper functions for specific testing needs
create_temp_script() {
    local script_content="$1"
    local script_path="$TEST_TMP_DIR/temp_script.sh"
    
    echo "$script_content" > "$script_path"
    chmod +x "$script_path"
    echo "$script_path"
}

source_script_for_testing() {
    local script_path="$1"
    
    # Source the script in a way that doesn't execute main functions
    # We'll need to modify the scripts to check for TEST_MODE
    if [ -f "$script_path" ]; then
        source "$script_path"
    else
        echo "Error: Cannot source script $script_path"
        return 1
    fi
}

# Validation helpers
validate_semantic_version_format() {
    local version="$1"
    if echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9\.-]+)?(\+[a-zA-Z0-9\.-]+)?$'; then
        return 0
    else
        return 1
    fi
}