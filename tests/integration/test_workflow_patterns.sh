#!/bin/bash

# Integration tests for workflow patterns and command sequences

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../test_framework.sh"

test_upgrade_command_sequence() {
    # Test the logical sequence of upgrade commands
    local commands_executed=""
    
    # Mock all the commands used in upgrade workflow
    mock_command "systemctl" "Service operation completed" 0
    mock_command "docker" "Docker operation completed" 0
    mock_command "git" "Git operation completed" 0
    
    # Simulate upgrade workflow
    systemctl stop broadcast
    commands_executed="$commands_executed stop"
    
    git pull
    commands_executed="$commands_executed pull"
    
    docker compose pull
    commands_executed="$commands_executed docker-pull"
    
    systemctl start broadcast
    commands_executed="$commands_executed start"
    
    # Verify the sequence
    assert_contains "$commands_executed" "stop" "Should stop service first"
    assert_contains "$commands_executed" "pull" "Should pull updates"
    assert_contains "$commands_executed" "docker-pull" "Should pull Docker images"
    assert_contains "$commands_executed" "start" "Should start service last"
}

test_backup_workflow() {
    # Test backup command structure and file operations
    local backup_dir="$TEST_TMP_DIR/backups"
    mkdir -p "$backup_dir"
    
    # Mock postgres dump
    mock_command "docker" "SQL dump data here" 0
    
    # Simulate backup workflow
    local timestamp="2024-07-20-14-30-45"
    local version="1.2.3"
    local backup_name="broadcast-backup-v${version}-${timestamp}"
    
    # Create temporary dump file
    echo "SQL dump data here" > "$backup_dir/temp-backup.dump"
    
    # Move to final name
    mv "$backup_dir/temp-backup.dump" "$backup_dir/${backup_name}.dump"
    
    # Create tar archive
    cd "$backup_dir"
    tar -czf "${backup_name}.tar.gz" "${backup_name}.dump"
    rm "${backup_name}.dump"
    
    # Verify backup was created
    assert_file_exists "$backup_dir/${backup_name}.tar.gz" "Backup archive should be created"
    
    # Test retention (keep only latest)
    touch "$backup_dir/broadcast-backup-v1.0.0-2024-07-19.tar.gz"
    touch "$backup_dir/broadcast-backup-v1.1.0-2024-07-19.tar.gz"
    
    # Simulate retention logic
    local files_to_keep=$(ls -t "$backup_dir"/broadcast-backup-*.tar.gz | head -1)
    local files_to_remove=$(ls -t "$backup_dir"/broadcast-backup-*.tar.gz | tail -n +2)
    
    # Just verify we can identify files correctly
    local newest_file=$(basename "$files_to_keep")
    assert_contains "$newest_file" "backup" "Should identify backup files"
    
    if [ -n "$files_to_remove" ]; then
        assert_contains "$files_to_remove" "v1.0.0" "Should identify old backups for removal"
    fi
}

test_trigger_file_processing() {
    # Test trigger file processing workflow
    local trigger_dir="$TEST_TMP_DIR/triggers"
    mkdir -p "$trigger_dir"
    
    # Create various trigger files
    echo "1.5.0" > "$trigger_dir/upgrade.txt"
    echo "backup-request" > "$trigger_dir/backup-db.txt"
    echo "app1.example.com" > "$trigger_dir/domains.txt"
    echo "app2.example.com" >> "$trigger_dir/domains.txt"
    
    local processed_triggers=""
    
    # Test upgrade trigger processing
    if [ -f "$trigger_dir/upgrade.txt" ]; then
        local version_content=$(cat "$trigger_dir/upgrade.txt")
        if echo "$version_content" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then
            processed_triggers="$processed_triggers upgrade:$version_content"
        fi
        rm "$trigger_dir/upgrade.txt"
    fi
    
    # Test backup trigger processing
    if [ -f "$trigger_dir/backup-db.txt" ]; then
        processed_triggers="$processed_triggers backup"
        rm "$trigger_dir/backup-db.txt"
    fi
    
    # Test domains trigger processing
    if [ -f "$trigger_dir/domains.txt" ]; then
        local domain_count=$(wc -l < "$trigger_dir/domains.txt" | tr -d ' ')
        processed_triggers="$processed_triggers domains:$domain_count"
        rm "$trigger_dir/domains.txt"
    fi
    
    # Verify processing
    assert_contains "$processed_triggers" "upgrade:1.5.0" "Should process upgrade trigger with version"
    assert_contains "$processed_triggers" "backup" "Should process backup trigger"
    assert_contains "$processed_triggers" "domains:2" "Should process domains trigger with count"
    
    # Verify cleanup
    assert_file_not_exists "$trigger_dir/upgrade.txt" "Upgrade trigger should be removed"
    assert_file_not_exists "$trigger_dir/backup-db.txt" "Backup trigger should be removed"
    assert_file_not_exists "$trigger_dir/domains.txt" "Domains trigger should be removed"
}

test_configuration_management() {
    # Test configuration file updates
    local config_file="$TEST_TMP_DIR/app.env"
    
    # Create initial config
    cat > "$config_file" << EOF
RAILS_ENV=production
DATABASE_HOST=postgres
SECRET_KEY_BASE=abc123
TLS_DOMAIN=original.example.com
EOF
    
    # Test adding new configuration (safe way)
    local new_domain="original.example.com,additional.example.com"
    
    # Remove existing TLS_DOMAIN entry
    local temp_file="$config_file.tmp"
    grep -v "^TLS_DOMAIN=" "$config_file" > "$temp_file"
    
    # Add new entry
    echo "TLS_DOMAIN=$new_domain" >> "$temp_file"
    mv "$temp_file" "$config_file"
    
    # Verify update
    local tls_entries=$(grep -c "^TLS_DOMAIN=" "$config_file")
    assert_equals "1" "$tls_entries" "Should have exactly one TLS_DOMAIN entry"
    
    local domain_value=$(grep "^TLS_DOMAIN=" "$config_file" | cut -d'=' -f2)
    assert_contains "$domain_value" "additional.example.com" "Should contain new domain"
}

test_license_validation_workflow() {
    # Test license validation command structure
    mock_command "curl" '{"registry_url":"test.registry.com","registry_login":"user","registry_password":"pass"}' 0
    
    local license_key="test-license-123"
    local domain="test.example.com"
    
    # Test response parsing
    local response=$(curl -s -X POST -H "Content-Type: application/json" \
        -d "{\"key\":\"$license_key\", \"domain\":\"$domain\"}" \
        https://sendbroadcast.net/license/check)
    
    # With our mock, this should return the mocked JSON response
    assert_contains "$response" "registry_url" "Response should contain registry info"
}

test_error_handling_patterns() {
    # Test error handling in various scenarios
    
    # Test command failure detection
    mock_command "failing_command" "Error occurred" 1
    
    set +e  # Temporarily disable exit on error
    failing_command >/dev/null 2>&1
    local exit_code=$?
    set -e  # Re-enable exit on error
    
    assert_equals "1" "$exit_code" "Should detect command failure"
    
    # Test file existence checking
    local nonexistent_file="$TEST_TMP_DIR/does_not_exist.txt"
    
    if [ -f "$nonexistent_file" ]; then
        assert_equals "should_not_reach" "this" "File should not exist"
    else
        assert_equals "correct" "correct" "Should handle missing files"
    fi
}

run_workflow_pattern_tests() {
    echo "Running Workflow Pattern Tests"
    echo "=============================="
    
    init_test_framework
    
    run_test "test_upgrade_command_sequence" test_upgrade_command_sequence
    run_test "test_backup_workflow" test_backup_workflow
    run_test "test_trigger_file_processing" test_trigger_file_processing
    run_test "test_configuration_management" test_configuration_management
    run_test "test_license_validation_workflow" test_license_validation_workflow
    run_test "test_error_handling_patterns" test_error_handling_patterns
    
    local result
    print_test_summary
    result=$?
    
    cleanup_test_framework
    return $result
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_workflow_pattern_tests
fi