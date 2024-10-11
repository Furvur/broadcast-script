function monitor() {
    # Get CPU information
    cpu_cores=$(nproc)
    cpu_load=$(uptime | awk -F'average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')

    # Get memory information
    mem_total=$(free -b | awk '/Mem:/ {print $2}')
    mem_used=$(free -b | awk '/Mem:/ {print $3}')
    mem_free_percent=$(free | awk '/Mem:/ {print $4/$2 * 100.0}')

    # Get disk information
    disk_total=$(df -B1 / | awk 'NR==2 {print $2}')
    disk_used=$(df -B1 / | awk 'NR==2 {print $3}')
    disk_free_percent=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    disk_free_percent=$(echo "100 - $disk_free_percent" | bc)

    # Create JSON output
    json_output=$(cat <<EOF
{
    "cpu_cores": $cpu_cores,
    "cpu_load": $cpu_load,
    "memory_used": $mem_used,
    "memory_total": $mem_total,
    "memory_free_percent": $mem_free_percent,
    "disk_space_total": $disk_total,
    "disk_space_used": $disk_used,
    "disk_space_free_percent": $disk_free_percent
}
EOF
)

    # Write JSON to file as broadcast user
    su - broadcast -c "echo '$json_output' > /opt/broadcast/app/monitor/system.json"
}
