#!/bin/bash

# DNS cache management for stopbrowsing

# Flush DNS cache aggressively
flush_dns_cache() {
    echo "Flushing DNS caches..."
    local flushed=false
    
    # Flush systemd-resolved (most modern Ubuntu systems)
    if command -v resolvectl >/dev/null 2>&1; then
        if sudo resolvectl flush-caches 2>/dev/null; then
            flushed=true
        fi
    fi
    
    # Try older systemd-resolve command
    if command -v systemd-resolve >/dev/null 2>&1; then
        if sudo systemd-resolve --flush-caches 2>/dev/null; then
            flushed=true
        fi
    fi
    
    # Restart systemd-resolved service for maximum effect
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        if sudo systemctl restart systemd-resolved 2>/dev/null; then
            flushed=true
        fi
    fi
    
    # Try dnsmasq
    if ! $flushed && command -v dnsmasq >/dev/null 2>&1; then
        if sudo systemctl restart dnsmasq 2>/dev/null; then
            flushed=true
        fi
    fi
    
    # Try nscd
    if ! $flushed && command -v nscd >/dev/null 2>&1; then
        if sudo systemctl restart nscd 2>/dev/null; then
            flushed=true
        fi
    fi
    
    # Try network-manager
    if ! $flushed && command -v nmcli >/dev/null 2>&1; then
        if sudo systemctl restart NetworkManager 2>/dev/null; then
            flushed=true
        fi
    fi
    
    if $flushed; then
        echo "DNS cache flushed"
    else
        echo "Warning: Could not flush DNS cache automatically"
        echo "You may need to restart your browser or run:"
        echo "  sudo systemctl restart systemd-resolved"
    fi
}

# Test if website is accessible
test_website_access() {
    local website="$1"
    local timeout="${2:-5}"
    
    # Try to resolve the hostname
    if host "$website" >/dev/null 2>&1; then
        # Try HTTP connection
        if curl -s --max-time "$timeout" --head "http://$website" >/dev/null 2>&1; then
            return 0
        fi
        # Try HTTPS connection
        if curl -s --max-time "$timeout" --head "https://$website" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    return 1
}

# Verify blocking is working
verify_blocking() {
    local failed_blocks=()
    
    echo "Verifying blocks..."
    
    for website in "${WEBSITES[@]}"; do
        if test_website_access "$website" 3; then
            failed_blocks+=("$website")
        fi
    done
    
    if [[ ${#failed_blocks[@]} -eq 0 ]]; then
        echo "All websites are successfully blocked"
        return 0
    else
        echo "Warning: These websites may still be accessible:"
        printf '  - %s\n' "${failed_blocks[@]}"
        echo ""
        echo "This could be due to:"
        echo "  - DNS caching"
        echo "  - Browser caching" 
        echo "  - Alternative DNS servers"
        echo "  - VPN or proxy usage"
        return 1
    fi
}