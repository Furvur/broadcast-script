# Broadcast Script Test Suite

Comprehensive testing framework for the Broadcast email automation deployment scripts.

## Overview

This test suite provides thorough coverage for the bash scripts used to deploy and manage the Broadcast email automation system. It includes unit tests, integration tests, and mocked external dependency tests to ensure reliability and security.

## Test Structure

```
tests/
├── test_framework.sh              # Core testing framework with assertions and mocking
├── run_all_tests.sh               # Main test runner  
├── simple_test.sh                 # Basic framework functionality test
├── README.md                      # This documentation
├── unit/                          # Unit tests for individual functions
│   └── test_version_functions.sh  # Tests for version validation and logic patterns
├── integration/                   # Integration tests for complete workflows
│   └── test_workflow_patterns.sh  # Tests for upgrade, backup, and trigger workflows
├── mocks/                         # Tests with mocked external dependencies
│   └── test_functional_patterns.sh # Functional pattern and external dependency tests
└── fixtures/                      # Test data and configuration files (empty)
```

## Running Tests

### Run All Tests
```bash
./tests/run_all_tests.sh
```

### Run Specific Test Suite
```bash
# Unit tests only
./tests/run_all_tests.sh -s unit

# Integration tests only
./tests/run_all_tests.sh -s integration

# Mock tests only
./tests/run_all_tests.sh -s mocks
```

### Run Tests with Pattern Matching
```bash
# Run tests matching "backup"
./tests/run_all_tests.sh -p backup

# Run tests matching "upgrade" with verbose output
./tests/run_all_tests.sh -v -p upgrade
```

### Verbose Output
```bash
# Run all tests with detailed output
./tests/run_all_tests.sh -v
```

## Test Categories

### Unit Tests (`tests/unit/`)

Test individual functions and logic patterns in isolation.

**test_version_functions.sh:**
- Semantic version regex validation
- Version comparison logic using `sort -V`
- Backup filename generation patterns
- Backup file retention logic
- Safe configuration file update patterns
- Docker command structure validation
- License validation payload patterns

### Integration Tests (`tests/integration/`)

Test complete workflows and command sequences.

**test_workflow_patterns.sh:**
- Upgrade command sequence (stop→update→pull→start)
- Backup workflow with file retention logic
- Trigger file processing for upgrades, backups, and domains
- Configuration file management and atomic updates
- License validation API interaction patterns
- Error handling and edge case scenarios

### Mock Tests (`tests/mocks/`)

Test functional patterns and external dependency interactions using mocks.

**test_functional_patterns.sh:**
- Docker login functionality testing
- Safe environment variable loading patterns
- Atomic configuration file management
- Input validation with proper semantic versioning
- Command execution with proper parameter handling
- Safe file operation patterns for backups
- Network request patterns with HTTPS and timeouts

## Test Framework Features

### Assertions
- `assert_equals(expected, actual, message)`
- `assert_not_equals(not_expected, actual, message)`
- `assert_contains(haystack, needle, message)`
- `assert_file_exists(file_path, message)`
- `assert_file_not_exists(file_path, message)`
- `assert_exit_code(expected_code, command, message)`

### Mocking
- `mock_command(command, output, exit_code)` - Mock external commands
- `assert_command_called(command, count, message)` - Verify command calls

### Test Environment
- Isolated temporary directories for each test
- Clean environment setup and teardown
- Configurable mock paths and dependencies

## Functional Validation

The test suite validates proper functionality and best practices:

1. **Secure Authentication**: Tests demonstrate proper Docker login patterns
2. **Safe Configuration**: Tests validate atomic configuration file updates
3. **Input Validation**: Tests ensure semantic version checking works correctly
4. **Command Safety**: Tests validate proper command parameter handling

## CI/CD Integration

The test runner returns appropriate exit codes for CI/CD integration:
- `0`: All tests passed
- `1`: Some tests failed

Example GitHub Actions integration:
```yaml
- name: Run Broadcast Script Tests
  run: |
    cd broadcast-script
    ./tests/run_all_tests.sh
```

## Writing New Tests

### Adding Unit Tests
1. Create test file in `tests/unit/`
2. Source the test framework: `source "$SCRIPT_DIR/../test_framework.sh"`
3. Create setup/teardown functions
4. Write test functions with assertions
5. Add test runner function
6. Update `run_all_tests.sh` to include new tests

### Test Function Pattern
```bash
test_function_name() {
    setup_test_env
    
    # Test implementation
    local result=$(function_under_test "param")
    assert_equals "expected" "$result" "Test description"
    
    teardown_test_env
}
```

### Mocking External Commands
```bash
# Mock a command with specific output and exit code
mock_command "curl" '{"status":"success"}' 0

# Test the mocked command
local output=$(curl https://example.com)
assert_contains "$output" "success" "Should return success"
```

## Known Limitations

1. **Docker Testing**: Full Docker integration tests require Docker to be running
2. **Root Privileges**: Some tests simulate but cannot fully test root-required operations
3. **Network Dependencies**: External API tests use mocks rather than real network calls
4. **System Commands**: System-level commands are mocked for portability

## Troubleshooting

### Tests Fail to Run
- Ensure all test files are executable: `find tests/ -name "*.sh" -exec chmod +x {} \;`
- Check that test framework exists: `ls -la tests/test_framework.sh`

### Mock Commands Not Working
- Verify `$PATH` includes the mock directory
- Check mock scripts are executable in `$TEST_TMP_DIR/mocks/`

### Permission Errors
- Some tests may require write permissions to `/tmp/`
- Ensure the test user can create temporary directories

## Contributing

1. Add tests for any new functionality
2. Update existing tests when modifying script behavior
3. Ensure all tests pass before submitting changes
4. Add documentation for complex test scenarios

## Test Coverage

Current test coverage includes:
- ✅ Version management and validation
- ✅ Backup and restore operations
- ✅ Upgrade and downgrade workflows  
- ✅ Trigger system functionality
- ✅ External dependency interactions
- ✅ Safe configuration management
- ✅ Command execution patterns
- ✅ Error handling scenarios

Areas for future expansion:
- Installation workflow testing
- SSL certificate management
- Database initialization
- Log rotation and cleanup
- Network security validation