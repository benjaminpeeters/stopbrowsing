#!/bin/bash

# stopbrowsing - Website blocker for productivity
# Copyright (C) 2025 Benjamin Peeters
# Licensed under AGPL-3.0

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/lib"
readonly CONFIG_DIR="${HOME}/.config/stopbrowsing"
readonly CONFIG_FILE="${CONFIG_DIR}/config.yaml"
readonly DEFAULT_CONFIG="${SCRIPT_DIR}/config/default.yaml"
readonly DATA_DIR="${HOME}/.local/share/stopbrowsing"
readonly REDIRECT_PAGE_DIR="${DATA_DIR}/redirect"
readonly PROFILES_DIR="${CONFIG_DIR}/profiles"

# Load library modules
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/hosts.sh"
source "${LIB_DIR}/schedule.sh"
source "${LIB_DIR}/stats.sh"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

usage() {
    echo -e "${BOLD}stopbrowsing${NC} - Website blocker for productivity"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    stopbrowsing [COMMAND]"
    echo ""
    echo -e "${BOLD}COMMANDS:${NC}"
    echo "    --help, -h          Show this help message"
    echo "    --config, -c        Edit configuration file"
    echo "    --status, -s        Show current blocking status and statistics"
    echo "    --list, -l          Show currently blocked websites"
    echo "    --edit-sites, -e    Edit website blocklist for current profile"
    echo "    --auto              Enable auto-blocking on login"
    echo "    --no-auto           Disable auto-blocking on login"
    echo "    --reset             Reset all configuration to defaults"
    echo ""
    echo "    --block             Block websites from configuration"
    echo "    --unblock           Unblock all websites"
    echo "    --add WEBSITE       Add website to current profile"
    echo "    --remove WEBSITE    Remove website from current profile"
    echo ""
    echo -e "${BOLD}CONFIGURATION:${NC}"
    echo -e "    Configuration file: ${CONFIG_FILE}"
    echo -e "    Default template:   ${DEFAULT_CONFIG}"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    stopbrowsing --config       # Edit blocking configuration"
    echo "    stopbrowsing --status       # Check blocking status and stats"
    echo "    stopbrowsing --list         # Show currently blocked websites"
    echo "    stopbrowsing --edit-sites   # Edit website blocklist directly"
    echo "    stopbrowsing --auto         # Enable auto-blocking on login"
    echo "    stopbrowsing --block        # Block websites now"
    echo "    stopbrowsing --add reddit.com # Add website to blocklist"
    echo ""
    echo "For more information, see: README.md"
}

show_status() {
    echo -e "${BOLD}🚫 StopBrowsing Status${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo -e "${YELLOW}⚠️  No configuration found${NC}"
        echo -e "Run ${BOLD}stopbrowsing --config${NC} to set up your website blocking"
        return 0
    fi
    
    echo -e "📁 Config: ${BLUE}${CONFIG_FILE}${NC}"
    echo -e "🌐 Profile: ${BLUE}$(config_get_profile)${NC}"
    
    # Show blocking status
    if is_blocked; then
        echo -e "🔴 Status: ${RED}BLOCKED${NC}"
        local blocked_count=$(get_blocked_websites | wc -l)
        echo -e "📊 Blocked: ${blocked_count} websites"
        
        # Show block start time
        local block_start=$(config_get_last_block_time)
        if [[ -n "$block_start" ]]; then
            echo -e "⏰ Since: ${block_start}"
        fi
    else
        echo -e "🟢 Status: ${GREEN}NOT BLOCKED${NC}"
    fi
    
    # Show auto-block status
    if [[ "$(config_get_auto_block_on_login)" == "true" ]]; then
        echo -e "🚀 Auto-block: ${GREEN}Enabled${NC}"
    else
        echo -e "🚀 Auto-block: ${YELLOW}Disabled${NC}"
        echo -e "Run ${BOLD}stopbrowsing --auto${NC} to enable auto-blocking on login"
    fi
    
    echo ""
    echo -e "${BOLD}📈 Success Statistics:${NC}"
    stats_show_summary
}

show_blocked_websites() {
    echo -e "${BOLD}🔴 Currently Blocked Websites${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if ! is_blocked; then
        echo -e "${GREEN}✅ No websites are currently blocked${NC}"
        echo ""
        echo "Run 'stopbrowsing block' to start blocking websites"
        return 0
    fi
    
    local profile=$(config_get_profile)
    echo -e "🌐 Profile: ${BLUE}${profile}${NC}"
    echo ""
    
    # Show blocked websites
    local blocked_sites=$(get_blocked_websites)
    if [[ -n "$blocked_sites" ]]; then
        echo -e "${BOLD}📋 Blocked Sites:${NC}"
        echo "$blocked_sites" | sed 's/^/  🚫 /'
        
        local count=$(echo "$blocked_sites" | wc -l)
        echo ""
        echo -e "📊 Total: ${count} websites blocked"
    else
        echo -e "${YELLOW}⚠️  No websites found in hosts file${NC}"
    fi
    
    # Show exceptions if any
    local exceptions=$(config_get_exceptions "$profile")
    if [[ -n "$exceptions" ]]; then
        echo ""
        echo -e "${BOLD}✅ Exceptions (Allowed):${NC}"
        echo "$exceptions" | sed 's/^/  ✅ /'
        
        local exc_count=$(echo "$exceptions" | wc -l)
        echo ""
        echo -e "📋 ${exc_count} exception(s) configured"
    fi
}

edit_sites_interactive() {
    local profile=$(config_get_profile)
    local profile_file="${CONFIG_DIR}/profiles/${profile}.yaml"
    
    # Copy from default if user profile doesn't exist
    if [[ ! -f "$profile_file" ]]; then
        mkdir -p "${CONFIG_DIR}/profiles"
        cp "${SCRIPT_DIR}/config/profiles/${profile}.yaml" "$profile_file" 2>/dev/null || {
            echo -e "${RED}Error:${NC} Profile '$profile' not found" >&2
            return 1
        }
        echo -e "✅ Created user profile: $profile_file"
    fi
    
    # Use preferred editor or fallback to nano
    local editor="${EDITOR:-nano}"
    
    echo -e "${BOLD}📝 Editing website blocklist for profile: ${BLUE}${profile}${NC}"
    echo -e "File: ${BLUE}${profile_file}${NC}"
    echo ""
    echo -e "${YELLOW}💡 Tip:${NC} Add websites under 'websites:', exceptions under 'exceptions:'"
    echo -e "Example exception: ${BLUE}!youtube.com/watch?v=specific_video${NC}"
    echo ""
    
    # Open editor
    "${editor}" "${profile_file}"
    
    # Validate after editing and update blocking if active
    if [[ -f "$profile_file" ]]; then
        echo -e "${GREEN}✅ Website list updated${NC}"
        
        # Reload profile and resynchronize if currently blocking
        load_profile "$profile"
        
        if is_blocked; then
            echo "Resynchronizing with new website list..."
            cmd_block --quiet
        fi
    else
        echo -e "${RED}❌ Error editing website list${NC}"
        return 1
    fi
}

enable_auto_blocking() {
    echo -e "${BOLD}🚀 Enabling Auto-Blocking Service${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Create config and data directories
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "${DATA_DIR}"
    mkdir -p "${REDIRECT_PAGE_DIR}"
    
    # Copy default config if not exists
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        cp "${DEFAULT_CONFIG}" "${CONFIG_FILE}"
        echo -e "✅ Created default configuration"
    fi
    
    # Enable auto-blocking in config
    config_set_auto_block_on_login "true"
    echo -e "✅ Enabled auto-blocking on login in config"
    
    # No redirect page needed anymore
    
    # Install systemd user service
    local service_file="${HOME}/.config/systemd/user/stopbrowsing.service"
    mkdir -p "$(dirname "${service_file}")"
    
    cat > "${service_file}" << EOF
[Unit]
Description=StopBrowsing Website Blocker
After=network.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_DIR}/stopbrowsing.sh block --startup
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
    
    # Enable and start service
    systemctl --user daemon-reload
    systemctl --user enable stopbrowsing.service
    
    # Start blocking immediately if enabled
    if [[ "$(config_get_enabled)" == "true" ]]; then
        systemctl --user start stopbrowsing.service
        echo -e "✅ Service started and blocking activated"
    else
        echo -e "✅ Service installed but not started (disabled in config)"
    fi
    
    echo -e "✅ Service will auto-start on login"
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo -e "1. Run ${BOLD}stopbrowsing --config${NC} to customize your blocking settings"
    echo -e "2. Run ${BOLD}stopbrowsing --status${NC} to verify everything is working"
    echo -e "3. Logout and login to test auto-blocking on login"
}

disable_auto_blocking() {
    echo -e "${BOLD}🔕 Disabling Auto-Blocking Service${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Stop and disable service
    systemctl --user stop stopbrowsing.service 2>/dev/null || true
    systemctl --user disable stopbrowsing.service 2>/dev/null || true
    
    # Remove service file
    rm -f "${HOME}/.config/systemd/user/stopbrowsing.service"
    systemctl --user daemon-reload
    
    # Disable auto-blocking in config
    config_set_auto_block_on_login "false"
    echo -e "✅ Disabled auto-blocking on login in config"
    
    # Unblock websites
    if is_blocked; then
        cmd_unblock --quiet
        echo -e "✅ Websites unblocked"
    fi
    
    echo -e "✅ Service stopped and disabled"
    echo ""
    echo -e "${YELLOW}Note:${NC} Configuration and statistics preserved in ${CONFIG_DIR}"
    echo -e "Remove manually if desired: ${BOLD}rm -rf ${CONFIG_DIR} ${DATA_DIR}${NC}"
}

reset_configuration() {
    echo -e "${BOLD}🔄 Resetting StopBrowsing Configuration${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${YELLOW}⚠️  This will reset ALL configuration and statistics to defaults${NC}"
    echo ""
    read -p "Are you sure you want to reset everything? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Unblock websites first
        if is_blocked; then
            echo "Unblocking websites..."
            cmd_unblock --quiet
        fi
        
        # Remove all configuration
        echo "Removing configuration files..."
        rm -rf "${CONFIG_DIR}"
        rm -rf "${DATA_DIR}"
        
        # Remove service
        systemctl --user stop stopbrowsing.service 2>/dev/null || true
        systemctl --user disable stopbrowsing.service 2>/dev/null || true
        rm -f "${HOME}/.config/systemd/user/stopbrowsing.service"
        systemctl --user daemon-reload 2>/dev/null || true
        
        # Recreate fresh configuration
        mkdir -p "${CONFIG_DIR}"
        mkdir -p "${DATA_DIR}"
        cp "${DEFAULT_CONFIG}" "${CONFIG_FILE}"
        
        echo -e "${GREEN}✅ Configuration reset to defaults${NC}"
        echo -e "Run ${BOLD}stopbrowsing --config${NC} to customize settings"
    else
        echo "Reset cancelled"
    fi
}

main() {
    case "${1:-}" in
        --help|-h)
            usage
            ;;
        --config|-c)
            config_edit
            ;;
        --status|-s)
            show_status
            ;;
        --list|-l)
            show_blocked_websites
            ;;
        --edit-sites|-e)
            edit_sites_interactive
            ;;
        --auto)
            enable_auto_blocking
            ;;
        --no-auto)
            disable_auto_blocking
            ;;
        --reset)
            reset_configuration
            ;;
        --block|block)
            shift
            cmd_block "$@"
            ;;
        --unblock|unblock)
            shift
            cmd_unblock "$@"
            ;;
        --add|add)
            shift
            cmd_add "$@"
            ;;
        --remove|remove)
            shift
            cmd_remove "$@"
            ;;
        "")
            show_status
            ;;
        *)
            echo -e "${RED}Error:${NC} Unknown command '${1}'" >&2
            echo -e "Use ${BOLD}stopbrowsing --help${NC} for usage information." >&2
            exit 1
            ;;
    esac
}

# Ensure required directories exist
[[ -d "${LIB_DIR}" ]] || { echo "Error: Library directory not found: ${LIB_DIR}" >&2; exit 1; }

# Initialize configuration
CURRENT_PROFILE=${CURRENT_PROFILE:-$(config_get_profile 2>/dev/null || echo "default")}
WEBSITES=()

# Load current profile if configuration exists
if [[ -f "${CONFIG_FILE}" ]]; then
    load_profile "$CURRENT_PROFILE"
fi

# Run main function with all arguments
main "$@"