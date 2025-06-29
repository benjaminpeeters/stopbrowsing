#!/bin/bash

# config.sh - Configuration management for stopbrowsing
# Copyright (C) 2025 Benjamin Peeters
# Licensed under AGPL-3.0

config_edit() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo -e "${YELLOW}⚠️  No configuration found. Creating from template...${NC}"
        mkdir -p "${CONFIG_DIR}"
        cp "${DEFAULT_CONFIG}" "${CONFIG_FILE}"
        echo -e "✅ Created: ${CONFIG_FILE}"
    fi
    
    # Use preferred editor or fallback to nano
    local editor="${EDITOR:-nano}"
    
    echo -e "${BOLD}📝 Opening configuration file...${NC}"
    echo -e "File: ${BLUE}${CONFIG_FILE}${NC}"
    echo ""
    
    # Open editor
    "${editor}" "${CONFIG_FILE}"
    
    echo -e "${GREEN}✅ Configuration updated${NC}"
    
    # Reload profile and resynchronize if currently blocking
    CURRENT_PROFILE="$(config_get_profile)"
    load_profile "$CURRENT_PROFILE"
    
    if is_blocked; then
        echo "Resynchronizing with new configuration..."
        cmd_block --quiet
    fi
}

config_validate() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "Error: Configuration file not found: ${CONFIG_FILE}" >&2
        return 1
    fi
    
    # Basic YAML syntax check (if yq is available)
    if command -v yq >/dev/null 2>&1; then
        if ! yq eval '.' "${CONFIG_FILE}" >/dev/null 2>&1; then
            echo "Error: Invalid YAML syntax in configuration file" >&2
            return 1
        fi
    fi
    
    # Check for required top-level keys
    if ! grep -q "^enabled:" "${CONFIG_FILE}"; then
        echo "Error: Missing required key 'enabled' in configuration" >&2
        return 1
    fi
    
    if ! grep -q "^profile:" "${CONFIG_FILE}"; then
        echo "Error: Missing required key 'profile' in configuration" >&2
        return 1
    fi
    
    return 0
}

config_get_enabled() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "true"  # Default to enabled
        return
    fi
    
    # Extract enabled value using basic bash parsing
    local enabled=$(grep "^enabled:" "${CONFIG_FILE}" | sed 's/enabled:[[:space:]]*//' | tr -d '"' | tr -d "'" | xargs)
    echo "${enabled:-true}"
}

config_get_profile() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "default"
        return
    fi
    
    # Extract profile value and remove comments
    local profile=$(grep "^profile:" "${CONFIG_FILE}" | sed 's/profile:[[:space:]]*//' | sed 's/#.*//' | tr -d '"' | tr -d "'" | xargs)
    echo "${profile:-default}"
}

config_get_websites() {
    local profile="${1:-$(config_get_profile)}"
    local profile_file="${CONFIG_DIR}/profiles/${profile}.yaml"
    
    # Fallback to script default if user profile doesn't exist
    if [[ ! -f "$profile_file" ]]; then
        profile_file="${SCRIPT_DIR}/config/profiles/${profile}.yaml"
    fi
    
    if [[ ! -f "$profile_file" ]]; then
        return
    fi
    
    # Extract websites from profile
    sed -n '/^websites:/,/^[a-zA-Z]/p' "$profile_file" | \
    grep "^[[:space:]]*-[[:space:]]" | \
    sed 's/^[[:space:]]*-[[:space:]]*//' | \
    sed 's/#.*//' | \
    xargs -I {} echo {}
}

config_get_exceptions() {
    local profile="${1:-$(config_get_profile)}"
    local profile_file="${CONFIG_DIR}/profiles/${profile}.yaml"
    
    # Fallback to script default if user profile doesn't exist
    if [[ ! -f "$profile_file" ]]; then
        profile_file="${SCRIPT_DIR}/config/profiles/${profile}.yaml"
    fi
    
    if [[ ! -f "$profile_file" ]]; then
        return
    fi
    
    # Extract exceptions from profile
    sed -n '/^exceptions:/,/^[a-zA-Z]/p' "$profile_file" | \
    grep "^[[:space:]]*-[[:space:]]" | \
    sed 's/^[[:space:]]*-[[:space:]]*//' | \
    sed 's/#.*//' | \
    tr -d '"' | tr -d "'" | \
    grep -v '^[[:space:]]*$' | \
    sed 's/^!//' | \
    xargs -I {} echo {}
}

# Load profile
load_profile() {
    local profile="$1"
    local profile_file="${CONFIG_DIR}/profiles/${profile}.yaml"
    
    # Fallback to script default if user profile doesn't exist
    if [[ ! -f "$profile_file" ]]; then
        profile_file="${SCRIPT_DIR}/config/profiles/${profile}.yaml"
    fi
    
    # Create user profile if neither exists
    if [[ ! -f "$profile_file" ]]; then
        create_default_profile "$profile"
        profile_file="${CONFIG_DIR}/profiles/${profile}.yaml"
    fi
    
    # Load websites from profile
    WEBSITES=()
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        
        # Extract website entries
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.+)$ ]]; then
            WEBSITES+=("${BASH_REMATCH[1]}")
        fi
    done < "$profile_file"
}

# Create default profile
create_default_profile() {
    local profile="${1:-default}"
    local profile_file="${CONFIG_DIR}/profiles/${profile}.yaml"
    
    mkdir -p "${CONFIG_DIR}/profiles"
    
    cat > "$profile_file" << 'EOF'
# Websites to block
websites:
  # Social media
  - facebook.com
  - www.facebook.com
  - twitter.com
  - www.twitter.com
  - x.com
  - www.x.com
  - instagram.com
  - www.instagram.com
  - tiktok.com
  - www.tiktok.com
  
  # Video platforms
  - youtube.com
  - www.youtube.com
  - m.youtube.com
  - youtu.be
  - www.youtu.be
  - netflix.com
  - www.netflix.com
  - twitch.tv
  - www.twitch.tv
  
  # News sites
  - reddit.com
  - www.reddit.com
  - old.reddit.com
  
  # Add more sites as needed
EOF
}

# Add website to profile
add_website_to_profile() {
    local website="$1"
    local profile="${2:-$CURRENT_PROFILE}"
    local profile_file="${CONFIG_DIR}/profiles/${profile}.yaml"
    
    # Check if already exists
    if grep -q "^[[:space:]]*-[[:space:]]*${website}[[:space:]]*$" "$profile_file" 2>/dev/null; then
        return 1
    fi
    
    # Add to file
    echo "  - $website" >> "$profile_file"
    return 0
}

# Remove website from profile
remove_website_from_profile() {
    local website="$1"
    local profile="${2:-$CURRENT_PROFILE}"
    local profile_file="${CONFIG_DIR}/profiles/${profile}.yaml"
    
    # Remove from file
    sed -i "/^[[:space:]]*-[[:space:]]*${website}[[:space:]]*$/d" "$profile_file" 2>/dev/null
}

config_get_last_block_time() {
    local last_block_file="${DATA_DIR}/last_block_time"
    if [[ -f "$last_block_file" ]]; then
        cat "$last_block_file" 2>/dev/null
    fi
}

config_get_doh_blocking_enabled() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "true"  # Default to enabled
        return
    fi
    
    # Extract doh_blocking enabled value
    local enabled=$(grep -A10 "^doh_blocking:" "${CONFIG_FILE}" | grep "enabled:" | sed 's/.*enabled:[[:space:]]*//' | sed 's/#.*//' | tr -d '"' | tr -d "'" | xargs)
    echo "${enabled:-true}"
}

# Individual layer control functions
config_get_hosts_blocking_enabled() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "true"  # Default to enabled
        return
    fi
    
    # Extract doh_blocking block_hosts_file value
    local enabled=$(grep -A10 "^doh_blocking:" "${CONFIG_FILE}" | grep "block_hosts_file:" | sed 's/.*block_hosts_file:[[:space:]]*//' | sed 's/#.*//' | tr -d '"' | tr -d "'" | xargs)
    echo "${enabled:-true}"
}

config_get_dot_blocking_enabled() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "true"  # Default to enabled
        return
    fi
    
    # Extract doh_blocking block_dot value
    local enabled=$(grep -A10 "^doh_blocking:" "${CONFIG_FILE}" | grep "block_dot:" | sed 's/.*block_dot:[[:space:]]*//' | sed 's/#.*//' | tr -d '"' | tr -d "'" | xargs)
    echo "${enabled:-true}"
}

config_get_doh_string_blocking_enabled() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "true"  # Default to enabled
        return
    fi
    
    # Extract doh_blocking block_doh value
    local enabled=$(grep -A10 "^doh_blocking:" "${CONFIG_FILE}" | grep "block_doh:" | sed 's/.*block_doh:[[:space:]]*//' | sed 's/#.*//' | tr -d '"' | tr -d "'" | xargs)
    echo "${enabled:-true}"
}

# Global variables for backwards compatibility
declare -a WEBSITES
CURRENT_PROFILE="$(config_get_profile)"
QUIET_MODE=false