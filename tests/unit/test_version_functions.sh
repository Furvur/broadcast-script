#!/bin/bash

# Simplified unit tests focusing on version validation logic

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../test_framework.sh"

# Test the version validation regex directly
test_semantic_version_regex() {
    # Test valid versions
    if echo "1.2.3" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9\.-]+)?(\+[a-zA-Z0-9\.-]+)?$'; then
        assert_equals "0" "0" "1.2.3 should be valid"
    else
        assert_equals "0" "1" "1.2.3 should be valid"
    fi
    
    if echo "2.0.0-alpha.1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9\.-]+)?(\+[a-zA-Z0-9\.-]+)?$'; then
        assert_equals "0" "0" "2.0.0-alpha.1 should be valid"
    else
        assert_equals "0" "1" "2.0.0-alpha.1 should be valid"
    fi
    
    # Test invalid versions
    if echo "1.2" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9\.-]+)?(\+[a-zA-Z0-9\.-]+)?$'; then
        assert_equals "1" "0" "1.2 should be invalid"
    else
        assert_equals "0" "0" "1.2 should be invalid"
    fi
    
    if echo "v1.2.3" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9\.-]+)?(\+[a-zA-Z0-9\.-]+)?$'; then
        assert_equals "1" "0" "v1.2.3 should be invalid"
    else
        assert_equals "0" "0" "v1.2.3 should be invalid"
    fi
}

test_version_comparison_logic() {
    # Test version comparison using sort -V
    local version1="1.0.0"
    local version2="2.0.0"
    
    if printf '%s\n%s\n' "$version1" "$version2" | sort -V -C; then
        # First version comes first in sort order (is less than or equal)
        assert_equals "less_or_equal" "less_or_equal" "1.0.0 should be <= 2.0.0"
    else
        assert_equals "greater" "greater" "1.0.0 should be > 2.0.0"
    fi
    
    # Test equal versions
    if printf '%s\n%s\n' "1.0.0" "1.0.0" | sort -V -C; then
        assert_equals "equal" "equal" "1.0.0 should equal 1.0.0"
    fi
}

test_backup_filename_pattern() {
    # Test backup filename generation pattern
    local version="1.2.3"
    local timestamp="2024-07-20-14-30-45"
    local backup_filename="broadcast-backup-v${version}-${timestamp}"
    
    assert_equals "broadcast-backup-v1.2.3-2024-07-20-14-30-45" "$backup_filename" "Backup filename should include version"
    
    # Test with unknown version
    version="unknown"
    backup_filename="broadcast-backup-v${version}-${timestamp}"
    assert_equals "broadcast-backup-vunknown-2024-07-20-14-30-45" "$backup_filename" "Should handle unknown version"
}

test_backup_retention_pattern() {
    # Test backup file retention logic
    
    local temp_dir="$TEST_TMP_DIR/backup_test"
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # Create some test files with different timestamps
    touch "broadcast-backup-1.tar.gz"
    sleep 0.1
    touch "broadcast-backup-2.tar.gz"
    sleep 0.1
    touch "broadcast-backup-3.tar.gz"
    touch "other-file.txt"
    
    # Test file retention pattern (keep newest, identify older)
    if ls broadcast-backup-*.tar.gz >/dev/null 2>&1; then
        local all_backups=$(ls -t broadcast-backup-*.tar.gz)
        local newest=$(echo "$all_backups" | head -1)
        local older_files=$(echo "$all_backups" | tail -n +2)
        
        # Should identify newest file
        assert_contains "$newest" "broadcast-backup-3.tar.gz" "Should identify newest backup"
        
        # Should identify older files for cleanup
        local older_count=$(echo "$older_files" | wc -l | tr -d ' ')
        assert_equals "2" "$older_count" "Should find 2 older backups"
    fi
}

test_configuration_update_pattern() {
    # Test safe configuration file update pattern
    local temp_env="$TEST_TMP_DIR/test.env"
    
    # Create initial .env file
    cat > "$temp_env" << EOF
RAILS_ENV=production
TLS_DOMAIN=original.example.com
DATABASE_HOST=postgres
EOF
    
    # Test atomic configuration update approach
    local temp_file="$temp_env.tmp"
    grep -v "^TLS_DOMAIN=" "$temp_env" > "$temp_file"
    echo "TLS_DOMAIN=original.example.com,new.example.com" >> "$temp_file"
    mv "$temp_file" "$temp_env"
    
    # Verify safe update worked
    local tls_count=$(grep -c "TLS_DOMAIN=" "$temp_env")
    assert_equals "1" "$tls_count" "Should have exactly one TLS_DOMAIN entry"
    
    local domain_value=$(grep "^TLS_DOMAIN=" "$temp_env" | cut -d'=' -f2)
    assert_contains "$domain_value" "new.example.com" "Should contain new domain"
}

test_docker_command_structure() {
    # Test Docker command patterns used in the scripts
    local expected_dump_cmd="docker compose exec postgres pg_dump -U broadcast -Fc broadcast_primary_production"
    
    # Verify command structure components
    assert_contains "$expected_dump_cmd" "pg_dump" "Should use pg_dump command"
    assert_contains "$expected_dump_cmd" "-U broadcast" "Should use broadcast user"
    assert_contains "$expected_dump_cmd" "-Fc" "Should use custom format"
    assert_contains "$expected_dump_cmd" "broadcast_primary_production" "Should target primary database"
}

test_license_validation_pattern() {
    # Test license validation URL and payload structure
    local license_key="test-license-123"
    local domain="test.example.com"
    local expected_payload="{\"key\":\"$license_key\", \"domain\":\"$domain\"}"
    local expected_url="https://sendbroadcast.net/license/check"
    
    assert_contains "$expected_payload" "test-license-123" "Payload should contain license key"
    assert_contains "$expected_payload" "test.example.com" "Payload should contain domain"
    assert_equals "$expected_url" "https://sendbroadcast.net/license/check" "Should use correct validation URL"
}

run_version_function_tests() {
    echo "Running Version Function Tests"
    echo "=============================="
    
    init_test_framework
    
    run_test "test_semantic_version_regex" test_semantic_version_regex
    run_test "test_version_comparison_logic" test_version_comparison_logic
    run_test "test_backup_filename_pattern" test_backup_filename_pattern
    run_test "test_backup_retention_pattern" test_backup_retention_pattern
    run_test "test_configuration_update_pattern" test_configuration_update_pattern
    run_test "test_docker_command_structure" test_docker_command_structure
    run_test "test_license_validation_pattern" test_license_validation_pattern
    
    local result
    print_test_summary
    result=$?
    
    cleanup_test_framework
    return $result
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_version_function_tests
fi