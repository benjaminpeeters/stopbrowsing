#!/bin/bash

# stats.sh - Statistics and success tracking for stopbrowsing
# Copyright (C) 2025 Benjamin Peeters
# Licensed under AGPL-3.0

# Get stats value from config
get_stat() {
    local key="$1"
    local default="$2"
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "$default"
        return
    fi
    
    local result=$(grep "^[[:space:]]*${key}:" "${CONFIG_FILE}" | \
    head -1 | cut -d':' -f2- | \
    sed 's/^[[:space:]]*//' | sed 's/#.*//' | sed 's/[[:space:]]*$//' | \
    sed 's/^"//' | sed 's/"$//')
    
    echo "${result:-$default}"
}

# Set stats value in config
set_stat() {
    local key="$1" 
    local value="$2"
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        return 1
    fi
    
    # Update or add the value
    if grep -q "^[[:space:]]*${key}:" "${CONFIG_FILE}"; then
        sed -i "s|^[[:space:]]*${key}:.*|  ${key}: \"$value\"|" "${CONFIG_FILE}"
    else
        # Add under statistics section if it exists
        if grep -q "^statistics:" "${CONFIG_FILE}"; then
            sed -i "/^statistics:/a\\  ${key}: \"$value\"" "${CONFIG_FILE}"
        fi
    fi
}

stats_show_summary() {
    local start_date=$(get_stat "start_date" "")
    
    if [[ -z "$start_date" ]]; then
        echo -e "  📅 Not started yet - first block will initialize tracking"
        return 0
    fi
    
    # Calculate days since start
    local start_epoch=$(date -d "$start_date" +%s 2>/dev/null || echo "0")
    local current_epoch=$(date +%s)
    local total_days=$(( (current_epoch - start_epoch) / 86400 ))
    
    if [[ $total_days -lt 0 ]]; then
        total_days=0
    fi
    
    local track_success=$(get_stat "track_success" "true")
    
    if [[ "$track_success" == "true" ]]; then
        echo -e "  📅 Start date: ${start_date}"
        echo -e "  📊 Total days: ${total_days}"
    fi
    
    # Show last block time from a separate data file
    local last_block_file="${DATA_DIR}/last_block_time"
    if [[ -f "$last_block_file" ]]; then
        local last_block=$(cat "$last_block_file" 2>/dev/null)
        if [[ -n "$last_block" ]]; then
            echo -e "  ⏰ Last block: ${last_block}"
        fi
    fi
}

stats_initialize() {
    local current_date=$(date '+%Y-%m-%d')
    
    # Set start date if not already set
    if [[ -z "$(get_stat "start_date")" ]]; then
        set_stat "start_date" "$current_date"
    fi
    
    # Set last block time in separate data file
    mkdir -p "${DATA_DIR}"
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "${DATA_DIR}/last_block_time"
}

stats_check_daily_increment() {
    local last_block_file="${DATA_DIR}/last_block_time"
    local current_date=$(date '+%Y-%m-%d')
    
    if [[ ! -f "$last_block_file" ]]; then
        return 0
    fi
    
    local last_block=$(cat "$last_block_file" 2>/dev/null)
    if [[ -z "$last_block" ]]; then
        return 0
    fi
    
    # Extract date from last block time
    local last_block_date="${last_block%% *}"
    
    # If last block was yesterday and we're still blocking, update last block time
    local yesterday=$(date -d "yesterday" '+%Y-%m-%d')
    
    if [[ "$last_block_date" == "$yesterday" ]] && is_blocked; then
        echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$last_block_file"
    fi
}