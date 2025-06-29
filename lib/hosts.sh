#!/bin/bash

# Reliable hosts file management for stopbrowsing
# Copyright (C) 2025 Benjamin Peeters
# Licensed under AGPL-3.0

HOSTS_FILE="/etc/hosts"
BLOCK_START="# BEGIN STOPBROWSING BLOCK"
BLOCK_END="# END STOPBROWSING BLOCK"
BACKUP_DIR="$HOME/.local/share/stopbrowsing/backups"

# Check if websites are currently blocked
is_blocked() {
    grep -q "$BLOCK_START" "$HOSTS_FILE" 2>/dev/null
}

# Get list of currently blocked websites
get_blocked_websites() {
    if is_blocked; then
        sed -n "/$BLOCK_START/,/$BLOCK_END/p" "$HOSTS_FILE" | \
        grep -E "^(127\.0\.0\.1|::1)" | \
        awk '{print $2}' | \
        sort -u
    fi
}

# Check if URL matches exception patterns
url_matches_exception() {
    local url="$1"
    local exception="$2"
    
    # Convert glob pattern to regex
    local pattern
    pattern=$(echo "$exception" | sed 's/\*/\.\*/g' | sed 's/\?/\./g')
    
    # Check if URL matches pattern
    if [[ "$url" =~ $pattern ]]; then
        return 0  # Match found
    fi
    
    return 1  # No match
}

# Check if domain should be blocked (considering exceptions)
should_block_domain() {
    local domain="$1"
    local profile="${2:-$(config_get_profile)}"
    
    # Get exceptions for this profile
    local exceptions=$(config_get_exceptions "$profile")
    
    # If no exceptions, block the domain
    if [[ -z "$exceptions" ]]; then
        return 0  # Should block
    fi
    
    # Check if domain matches any exception
    while IFS= read -r exception; do
        [[ -z "$exception" ]] && continue
        
        # Extract domain from exception pattern
        local exception_domain="${exception%%/*}"
        exception_domain="${exception_domain%%\?*}"
        exception_domain="${exception_domain%%:*}"
        
        # Check if it's a domain-wide exception
        if [[ "$exception" == "$domain" ]] || [[ "$exception" == "$domain/*" ]] || [[ "$exception" == "*.$domain" ]]; then
            return 1  # Should not block (exception found)
        fi
    done <<< "$exceptions"
    
    return 0  # Should block
}

# Terminate existing connections to blocked domains (gentle approach)
terminate_existing_connections() {
    local domains=("$@")
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        return 0
    fi
    
    echo "Terminating existing connections to blocked websites..."
    
    # Enhanced connection termination for persistent connections
    local terminated_count=0
    
    # Method 1: Kill existing connections using ss (socket statistics)
    for domain in "${domains[@]}"; do
        # Kill connections by destination domain
        if sudo ss -K dst "$domain" >/dev/null 2>&1; then
            terminated_count=$((terminated_count + 1))
        fi
        
        # Also try wildcard subdomains (for CDNs)
        sudo ss -K dst "*.$domain" >/dev/null 2>&1 || true
    done
    
    # Method 2: Reset network connections more aggressively
    # Flush connection tracking for blocked domains
    for domain in "${domains[@]}"; do
        # Remove connection tracking entries (if conntrack is available)
        if command -v conntrack >/dev/null 2>&1; then
            sudo conntrack -D -d "$domain" >/dev/null 2>&1 || true
        fi
    done
    
    # Method 3: Detect and offer browser restart
    detect_browser_connections "${domains[@]}"
    
    # Wait for connections to properly close
    sleep 2
    
    if [[ $terminated_count -gt 0 ]]; then
        echo "Connection termination complete ($terminated_count domains processed)"
    else
        echo "Connection termination complete"
    fi
}

# Detect browsers with active connections to blocked domains
detect_browser_connections() {
    local domains=("$@")
    local browsers_found=()
    
    # Common browser process names
    local browser_processes=("firefox" "chrome" "chromium" "brave" "brave-browser" "opera" "edge")
    
    for browser in "${browser_processes[@]}"; do
        if pgrep -f "$browser" >/dev/null 2>&1; then
            # Check if this browser has connections to blocked domains
            for domain in "${domains[@]}"; do
                if sudo ss -tulpn | grep -q "$domain.*$browser" 2>/dev/null; then
                    browsers_found+=("$browser")
                    break
                fi
            done
        fi
    done
    
    # Report browser connection status (informational only)
    if [[ ${#browsers_found[@]} -gt 0 ]]; then
        echo "ℹ️  Active browser connections detected: ${browsers_found[*]}"
        echo "   Blocking will take effect for new requests and connections"
    fi
}

# Aggressively flush DNS caches
flush_all_dns_caches() {
    echo "Flushing all DNS caches..."
    
    # Restart systemd-resolved (most effective)
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        sudo systemctl restart systemd-resolved
    fi
    
    # Flush resolvectl cache
    if command -v resolvectl >/dev/null 2>&1; then
        sudo resolvectl flush-caches 2>/dev/null || true
    fi
    
    # Flush systemd-resolve cache (older systems)
    if command -v systemd-resolve >/dev/null 2>&1; then
        sudo systemd-resolve --flush-caches 2>/dev/null || true
    fi
}

# Setup DoH blocking for specific domains to prevent DNS bypass
setup_doh_blocking() {
    local domains=("$@")
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        return 0
    fi
    
    echo "Setting up DoH blocking for ${#domains[@]} domains..."
    
    # Use iptables for reliable string matching (works better than nftables for this)
    if command -v iptables >/dev/null 2>&1; then
        # Create or flush custom iptables chain
        sudo iptables -N STOPBROWSING_DOH 2>/dev/null || sudo iptables -F STOPBROWSING_DOH 2>/dev/null || {
            echo "⚠️  WARNING: Could not setup iptables for DoH blocking"
            return 1
        }
        
        # Add chain to OUTPUT if not already present
        if ! sudo iptables -C OUTPUT -j STOPBROWSING_DOH 2>/dev/null; then
            sudo iptables -I OUTPUT -j STOPBROWSING_DOH 2>/dev/null || {
                echo "⚠️  WARNING: Could not add iptables chain to OUTPUT"
                return 1
            }
        fi
        
        # Block traffic containing blocked domains using string matching
        echo "Adding iptables string matching rules..."
        for domain in "${domains[@]}"; do
            echo "Adding rule for $domain"
            sudo iptables -A STOPBROWSING_DOH -p tcp --dport 443 -m string --string "$domain" --algo bm -j DROP 2>/dev/null || true
            sudo iptables -A STOPBROWSING_DOH -p tcp --dport 80 -m string --string "$domain" --algo bm -j DROP 2>/dev/null || true
        done
        
        echo "✅ DoH blocking enabled for ${#domains[@]} domains (iptables)"
        return 0
    else
        echo "⚠️  WARNING: No firewall tool available for DoH blocking"
        return 1
    fi
}

# Remove DoH blocking rules
remove_doh_blocking() {
    echo "Removing DoH blocking rules..."
    
    # Remove iptables rules
    if command -v iptables >/dev/null 2>&1; then
        sudo iptables -D OUTPUT -j STOPBROWSING_DOH 2>/dev/null || true
        sudo iptables -F STOPBROWSING_DOH 2>/dev/null || true
        sudo iptables -X STOPBROWSING_DOH 2>/dev/null || true
        echo "✅ DoH blocking rules removed (iptables)"
    fi
    
    # Remove nftables table if it exists
    if command -v nft >/dev/null 2>&1; then
        sudo nft delete table inet stopbrowsing 2>/dev/null || true
    fi
    
    return 0
}

# Check if DoH blocking is enabled
is_doh_blocking_enabled() {
    # Check for iptables first
    if command -v iptables >/dev/null 2>&1; then
        sudo iptables -L STOPBROWSING_DOH -n 2>/dev/null | grep -q "DROP" 2>/dev/null
    else
        return 1
    fi
}

# Setup DNS over TLS (DoT) blocking - simple and safe
setup_dot_blocking() {
    echo "Setting up DoT blocking (port 853)..."
    
    if ! command -v iptables >/dev/null 2>&1; then
        echo "⚠️  WARNING: iptables not available for DoT blocking"
        return 1
    fi
    
    # Create or flush DoT blocking chain
    sudo iptables -N STOPBROWSING_DOT 2>/dev/null || sudo iptables -F STOPBROWSING_DOT 2>/dev/null || {
        echo "⚠️  WARNING: Could not setup iptables chain for DoT blocking"
        return 1
    }
    
    # Add chain to OUTPUT if not already present
    if ! sudo iptables -C OUTPUT -j STOPBROWSING_DOT 2>/dev/null; then
        sudo iptables -I OUTPUT -j STOPBROWSING_DOT 2>/dev/null || {
            echo "⚠️  WARNING: Could not add DoT chain to OUTPUT"
            return 1
        }
    fi
    
    # Block all DNS over TLS traffic (port 853)
    sudo iptables -A STOPBROWSING_DOT -p tcp --dport 853 -j DROP 2>/dev/null || {
        echo "⚠️  WARNING: Could not add DoT TCP blocking rule"
        return 1
    }
    
    sudo iptables -A STOPBROWSING_DOT -p udp --dport 853 -j DROP 2>/dev/null || {
        echo "⚠️  WARNING: Could not add DoT UDP blocking rule"
        return 1
    }
    
    echo "✅ DoT blocking enabled (port 853 blocked)"
    return 0
}

# Remove DoT blocking rules
remove_dot_blocking() {
    echo "Removing DoT blocking rules..."
    
    if command -v iptables >/dev/null 2>&1; then
        sudo iptables -D OUTPUT -j STOPBROWSING_DOT 2>/dev/null || true
        sudo iptables -F STOPBROWSING_DOT 2>/dev/null || true
        sudo iptables -X STOPBROWSING_DOT 2>/dev/null || true
        echo "✅ DoT blocking rules removed"
    fi
    
    return 0
}

# Check if DoT blocking is enabled
is_dot_blocking_enabled() {
    if command -v iptables >/dev/null 2>&1; then
        sudo iptables -L STOPBROWSING_DOT -n 2>/dev/null | grep -q "dpt:853" 2>/dev/null
    else
        return 1
    fi
}

# Close streaming tabs using gentle window management
close_streaming_tabs() {
    echo "Closing streaming tabs..."
    
    # Check if xdotool is available
    if ! command -v xdotool >/dev/null 2>&1; then
        echo "⚠️  xdotool not found - tab closing unavailable"
        echo "   Install with: sudo apt install xdotool"
        return 1
    fi
    
    # Get tab closing configuration
    local websites=($(config_get_tab_closing_websites))
    local delay=$(config_get_tab_closing_delay)
    local closed_count=0
    local total_found=0
    
    echo "Searching for streaming tabs: ${websites[*]}"
    
    for website in "${websites[@]}"; do
        # Find windows matching this website
        local window_ids=$(xdotool search --onlyvisible --name "$website" 2>/dev/null)
        
        if [[ -n "$window_ids" ]]; then
            while IFS= read -r window_id; do
                if [[ -n "$window_id" ]]; then
                    total_found=$((total_found + 1))
                    local window_name=$(xdotool getwindowname "$window_id" 2>/dev/null)
                    echo "Found streaming tab: $window_name"
                    
                    # Gently close the tab using windowactivate + ctrl+w
                    if xdotool windowactivate "$window_id" 2>/dev/null; then
                        sleep "$delay"  # Wait for window to activate
                        xdotool key ctrl+w  # Close only the current tab
                        closed_count=$((closed_count + 1))
                        echo "Closed tab: $window_name"
                        
                        # Delay between closing tabs
                        sleep "$delay"
                    else
                        echo "⚠️  Could not activate window: $window_name"
                    fi
                fi
            done <<< "$window_ids"
        fi
    done
    
    if [[ $total_found -eq 0 ]]; then
        echo "No streaming tabs found to close"
    else
        echo "Closed $closed_count of $total_found streaming tabs"
    fi
    
    return 0
}

# Block websites using hosts file with improved reliability
block_websites() {
    local temp_file=$(mktemp)
    
    # Always remove existing blocks first for clean state
    if is_blocked; then
        echo "Updating website blocks..."
        remove_block_silent
    else
        echo "Adding website blocks..."
    fi
    
    # Filter websites based on exceptions
    local filtered_websites=()
    for website in "${WEBSITES[@]}"; do
        if should_block_domain "$website" "$CURRENT_PROFILE"; then
            filtered_websites+=("$website")
        fi
    done
    
    # Create hosts block section
    {
        echo "$BLOCK_START"
        echo "# Blocked on $(date)"
        echo "# Profile: $CURRENT_PROFILE"
        
        # Add filtered websites to hosts file
        for website in "${filtered_websites[@]}"; do
            echo "127.0.0.1 $website"
            echo "::1 $website"
        done
        
        echo "$BLOCK_END"
    } > "$temp_file"
    
    # Get individual layer settings
    local doh_enabled=$(config_get_doh_blocking_enabled)
    local hosts_enabled=$(config_get_hosts_blocking_enabled)
    local dot_enabled=$(config_get_dot_blocking_enabled)
    local doh_string_enabled=$(config_get_doh_string_blocking_enabled)
    local tab_closing_enabled=$(config_get_tab_closing_enabled)
    
    # Layer 1: Update hosts file (if enabled)
    local hosts_success=false
    if [[ "$hosts_enabled" == "true" ]]; then
        local backup_file="$BACKUP_DIR/hosts.$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        echo "Updating hosts file..."
        
        # Update hosts file (simplified approach)
        sudo cp "$HOSTS_FILE" "$backup_file" 2>/dev/null || echo "Warning: Could not backup hosts file"
        
        # Update hosts file and check if it actually worked
        sudo bash -c "cat '$temp_file' >> '$HOSTS_FILE'" 2>/dev/null
        
        # Verify the update worked by checking if our marker exists
        if grep -q "$BLOCK_START" "$HOSTS_FILE" 2>/dev/null; then
            hosts_success=true
            # Aggressively flush DNS caches
            flush_all_dns_caches
        else
            echo "Error: Failed to update hosts file"
        fi
    else
        echo "Skipping hosts file update (disabled in config)"
    fi
    
    # Layer 2 & 3: Setup DoH/DoT blocking to prevent DNS bypass (if enabled)
    local dot_success=false
    local doh_success=false
    
    # Layer 2: DoT blocking (if master switch and layer enabled)
    if [[ "$doh_enabled" == "true" && "$dot_enabled" == "true" ]]; then
        if setup_dot_blocking; then
            dot_success=true
        fi
    elif [[ "$dot_enabled" != "true" ]]; then
        echo "Skipping DoT blocking (disabled in config)"
    fi
    
    # Layer 3: DoH string matching (if master switch and layer enabled)  
    if [[ "$doh_enabled" == "true" && "$doh_string_enabled" == "true" ]]; then
        if setup_doh_blocking "${filtered_websites[@]}"; then
            doh_success=true
        fi
    elif [[ "$doh_string_enabled" != "true" ]]; then
        echo "Skipping DoH string matching (disabled in config)"
    fi
    
    # Layer 4: Tab closing (if enabled)
    local tab_closing_success=false
    if [[ "$tab_closing_enabled" == "true" ]]; then
        if close_streaming_tabs; then
            tab_closing_success=true
        fi
    else
        echo "Skipping tab closing (disabled in config)"
    fi
    
    local blocked_count=${#filtered_websites[@]}
    local exception_count=$((${#WEBSITES[@]} - blocked_count))
    
    if [[ $exception_count -gt 0 ]]; then
        echo "Blocked ${blocked_count} websites with ${exception_count} exceptions"
    else
        echo "Blocked ${blocked_count} websites"
    fi
    
    # Report all layer blocking status
    if [[ "$hosts_success" == "true" ]]; then
        echo "✅ Layer 1: Hosts file blocking enabled"
    elif [[ "$hosts_enabled" == "true" ]]; then
        echo "⚠️  Layer 1: Hosts file blocking failed"
    fi
    
    if [[ "$dot_success" == "true" ]]; then
        echo "✅ Layer 2: DoT blocking enabled (DNS over TLS blocked on port 853)"
    elif [[ "$doh_enabled" == "true" && "$dot_enabled" == "true" ]]; then
        echo "⚠️  Layer 2: DoT blocking failed - devices may use DNS-over-TLS"
    fi
    
    if [[ "$doh_success" == "true" ]]; then
        echo "✅ Layer 3: DoH blocking enabled (prevents browser DNS bypass)"
    elif [[ "$doh_enabled" == "true" && "$doh_string_enabled" == "true" ]]; then
        echo "⚠️  Layer 3: DoH blocking failed - browsers may bypass using DNS-over-HTTPS"
    fi
    
    if [[ "$tab_closing_success" == "true" ]]; then
        echo "✅ Layer 4: Tab closing enabled (closes streaming browser tabs)"
    elif [[ "$tab_closing_enabled" != "true" ]]; then
        echo "ℹ️  Layer 4: Tab closing disabled (streaming tabs will remain open)"
    else
        echo "⚠️  Layer 4: Tab closing failed (xdotool may not be installed)"
    fi
    
    # Clean up temp file
    rm -f "$temp_file"
    
    # Validate blocking worked
    echo "Validating blocking..."
    validate_blocking "${filtered_websites[0]:-}"
    
    return 0
}

# Remove block section silently (for internal use)
remove_block_silent() {
    if is_blocked; then
        local backup_file="$BACKUP_DIR/hosts.$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        sudo bash -c "cp '$HOSTS_FILE' '$backup_file' && sed -i '/$BLOCK_START/,/$BLOCK_END/d' '$HOSTS_FILE'" 2>/dev/null
    fi
}

# Remove block section
remove_block() {
    if is_blocked; then
        local backup_file="$BACKUP_DIR/hosts.$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        echo "Removing website blocks..."
        if sudo bash -c "cp '$HOSTS_FILE' '$backup_file' && sed -i '/$BLOCK_START/,/$BLOCK_END/d' '$HOSTS_FILE'"; then
            # Aggressively flush DNS caches
            flush_all_dns_caches
            
            # Remove DoH and DoT blocking rules
            remove_doh_blocking
            remove_dot_blocking
            
            return 0
        else
            echo "Error: Failed to update hosts file"
            return 1
        fi
    else
        echo "No blocks found to remove"
        return 1
    fi
}

# Validate that blocking actually works
validate_blocking() {
    local test_domain="$1"
    
    if [[ -z "$test_domain" ]]; then
        return 0
    fi
    
    # Test DNS resolution
    local resolved_ip=$(host "$test_domain" 2>/dev/null | grep "has address" | head -1 | awk '{print $4}')
    
    if [[ "$resolved_ip" == "127.0.0.1" ]]; then
        echo "✓ DNS blocking verified for $test_domain"
        return 0
    else
        echo "⚠ Warning: $test_domain may not be fully blocked (resolves to: $resolved_ip)"
        echo "  Try closing and reopening your browser"
        return 1
    fi
}

# Unblock websites
unblock_websites() {
    if ! is_blocked; then
        echo "No websites are currently blocked."
        return 1
    fi
    
    # Remove blocks
    if remove_block; then
        return 0
    else
        return 1
    fi
}

# Cleanup old backups (called after operations)
cleanup_old_backups() {
    # Keep only last 10 backups
    ls -t "$BACKUP_DIR"/hosts.* 2>/dev/null | tail -n +11 | xargs -r rm 2>/dev/null || true
}

# Restore hosts file from backup
restore_hosts() {
    local latest_backup=$(ls -t "$BACKUP_DIR"/hosts.* 2>/dev/null | head -1)
    
    if [[ -z "$latest_backup" ]]; then
        echo "No backup found to restore"
        return 1
    fi
    
    echo "Restoring from: $latest_backup"
    if sudo cp "$latest_backup" "$HOSTS_FILE"; then
        flush_all_dns_caches
        echo "Hosts file restored successfully"
        return 0
    else
        echo "Error: Failed to restore hosts file"
        return 1
    fi
}

# Log action to /tmp/stopbrowsing/
log_action() {
    local action="$1"
    local details="$2"
    
    mkdir -p "/tmp/stopbrowsing"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$$] $action: $details" >> "/tmp/stopbrowsing/activity.log"
}

# Command: block
cmd_block() {
    local duration=""
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--profile)
                CURRENT_PROFILE="$2"
                load_profile "$CURRENT_PROFILE"
                shift 2
                ;;
            -t|--time)
                duration="$2"
                shift 2
                ;;
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    # Block websites
    if block_websites; then        
        log_action "BLOCK" "Blocked ${#WEBSITES[@]} websites in profile $CURRENT_PROFILE"
        
        # Schedule unblock if duration specified
        if [[ -n "$duration" ]]; then
            schedule_unblock "$duration"
        fi
        
        echo "Successfully blocked ${#WEBSITES[@]} websites"
    else
        return 1
    fi
}

# Command: unblock  
cmd_unblock() {
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    # Unblock websites
    if unblock_websites; then
        log_action "UNBLOCK" "Unblocked all websites"
        cancel_scheduled_unblock
        
        echo "Successfully unblocked all websites"
    else
        return 1
    fi
}

# Command: status
cmd_status() {
    if is_blocked; then
        echo "Status: BLOCKED"
        echo ""
        echo "Currently blocked websites:"
        get_blocked_websites | sed 's/^/  - /'
        
        # Show DoH/DoT blocking status
        echo ""
        if is_dot_blocking_enabled; then
            echo "DoT blocking: ENABLED (DNS over TLS blocked on port 853)"
        else
            echo "DoT blocking: DISABLED (devices may use DNS-over-TLS)"
        fi
        
        if is_doh_blocking_enabled; then
            echo "DoH blocking: ENABLED (prevents DNS bypass)"
        else
            echo "DoH blocking: DISABLED (browsers may bypass blocking)"
        fi
        
        # Check for scheduled unblock
        if [[ -f "/tmp/stopbrowsing.unblock.at" ]]; then
            local unblock_time=$(cat "/tmp/stopbrowsing.unblock.at")
            echo ""
            echo "Scheduled to unblock at: $unblock_time"
        fi
    else
        echo "Status: NOT BLOCKED"
        echo "No websites are currently blocked"
        
        # Show DoH/DoT blocking status even when not blocking
        echo ""
        if is_dot_blocking_enabled; then
            echo "DoT blocking: ENABLED (leftover rules - run --unblock to clean)"
        fi
        
        if is_doh_blocking_enabled; then
            echo "DoH blocking: ENABLED (leftover rules - run --unblock to clean)"
        fi
    fi
}

# Command: list
cmd_list() {
    local profile="${1:-$CURRENT_PROFILE}"
    
    echo "Websites in profile '$profile':"
    echo ""
    
    # Load profile if different
    if [[ "$profile" != "$CURRENT_PROFILE" ]]; then
        load_profile "$profile"
    fi
    
    if [[ ${#WEBSITES[@]} -eq 0 ]]; then
        echo "  No websites configured in this profile"
    else
        printf '  - %s\n' "${WEBSITES[@]}"
        echo ""
        echo "Total: ${#WEBSITES[@]} websites"
    fi
}

# Command: add
cmd_add() {
    local website="$1"
    local profile="${2:-$CURRENT_PROFILE}"
    
    if [[ -z "$website" ]]; then
        echo "Error: Website not specified"
        echo "Usage: $(basename "$0") add <website> [profile]"
        return 1
    fi
    
    # Clean up website URL
    website="${website#http://}"
    website="${website#https://}"
    website="${website#www.}"
    website="${website%%/*}"
    
    if add_website_to_profile "$website" "$profile"; then
        echo "Added '$website' to profile '$profile'"
        
        # Reload profile if it's current
        if [[ "$profile" == "$CURRENT_PROFILE" ]]; then
            load_profile "$CURRENT_PROFILE"
        fi
        
        # Note: Run 'stopbrowsing --block' to apply changes if currently blocking
        if is_blocked && [[ "$profile" == "$CURRENT_PROFILE" ]]; then
            echo "Run 'stopbrowsing --block' to apply changes"
        fi
    else
        echo "Website '$website' already exists in profile '$profile'"
        return 1
    fi
}

# Command: remove
cmd_remove() {
    local website="$1"
    local profile="${2:-$CURRENT_PROFILE}"
    
    if [[ -z "$website" ]]; then
        echo "Error: Website not specified"
        echo "Usage: $(basename "$0") remove <website> [profile]"
        return 1
    fi
    
    # Clean up website URL
    website="${website#http://}"
    website="${website#https://}"
    website="${website#www.}"
    website="${website%%/*}"
    
    remove_website_from_profile "$website" "$profile"
    echo "Removed '$website' from profile '$profile'"
    
    # Reload profile if it's current
    if [[ "$profile" == "$CURRENT_PROFILE" ]]; then
        load_profile "$CURRENT_PROFILE"
    fi
    
    # Note: Run 'stopbrowsing --block' to apply changes if currently blocking
    if is_blocked && [[ "$profile" == "$CURRENT_PROFILE" ]]; then
        echo "Run 'stopbrowsing --block' to apply changes"
    fi
}