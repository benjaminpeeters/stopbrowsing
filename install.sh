#!/bin/bash

# StopBrowsing Installation Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/stopbrowsing"
DATA_DIR="$HOME/.local/share/stopbrowsing"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check requirements
check_requirements() {
    print_status "Checking requirements..."
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_error "Do not run this script as root"
        exit 1
    fi
    
    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        print_status "Testing sudo access..."
        if ! sudo true; then
            print_error "This script requires sudo access"
            exit 1
        fi
    fi
    
    # Check required commands
    local missing_commands=()
    for cmd in bash grep sed awk; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        print_error "Missing required commands: ${missing_commands[*]}"
        exit 1
    fi
    
    print_success "Requirements check passed"
}

# Install main script
install_script() {
    print_status "Installing stopbrowsing script..."
    
    # Make script executable
    chmod +x "$SCRIPT_DIR/stopbrowsing.sh"
    
    # Create symlink in /usr/local/bin
    if sudo ln -sf "$SCRIPT_DIR/stopbrowsing.sh" "$INSTALL_DIR/stopbrowsing"; then
        print_success "Script installed to $INSTALL_DIR/stopbrowsing"
    else
        print_error "Failed to install script"
        exit 1
    fi
}

# Setup configuration
setup_config() {
    print_status "Setting up configuration..."
    
    # Create config directories
    mkdir -p "$CONFIG_DIR/profiles"
    mkdir -p "$DATA_DIR/backups"
    
    # Copy default configuration if not exists
    if [[ ! -f "$CONFIG_DIR/config.yaml" ]]; then
        cp "$SCRIPT_DIR/config/default.yaml" "$CONFIG_DIR/config.yaml"
        print_success "Default configuration copied"
    else
        print_warning "Configuration already exists, skipping"
    fi
    
    # Copy default profiles
    for profile in "$SCRIPT_DIR/config/profiles"/*.yaml; do
        local profile_name=$(basename "$profile")
        local target="$CONFIG_DIR/profiles/$profile_name"
        
        if [[ ! -f "$target" ]]; then
            cp "$profile" "$target"
            print_success "Profile $profile_name copied"
        else
            print_warning "Profile $profile_name already exists, skipping"
        fi
    done
}

# Install systemd service
install_systemd_service() {
    print_status "Installing systemd service..."
    
    local service_file="/tmp/stopbrowsing.service"
    cat > "$service_file" << EOF
[Unit]
Description=StopBrowsing Website Blocker
After=network.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_DIR/stopbrowsing.sh block -q
ExecStop=$SCRIPT_DIR/stopbrowsing.sh unblock -q
RemainAfterExit=yes
User=$USER

[Install]
WantedBy=multi-user.target
EOF
    
    # Install service
    if sudo cp "$service_file" "/etc/systemd/system/stopbrowsing.service"; then
        sudo systemctl daemon-reload
        print_success "Systemd service installed"
        
        echo
        print_status "Service usage:"
        echo "  sudo systemctl start stopbrowsing    # Block websites"
        echo "  sudo systemctl stop stopbrowsing     # Unblock websites"
        echo "  sudo systemctl enable stopbrowsing   # Enable auto-start"
    else
        print_warning "Failed to install systemd service"
    fi
    
    rm -f "$service_file"
}

# Setup shell completion
setup_completion() {
    print_status "Setting up shell completion..."
    
    local completion_dir="$HOME/.local/share/bash-completion/completions"
    mkdir -p "$completion_dir"
    
    # Create basic completion script
    cat > "$completion_dir/stopbrowsing" << 'EOF'
_stopbrowsing() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    opts="block unblock status list add remove schedule install help"
    
    case "${prev}" in
        stopbrowsing)
            COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
            return 0
            ;;
        block)
            COMPREPLY=( $(compgen -W "-p --profile -t --time -f --force -q --quiet" -- ${cur}) )
            return 0
            ;;
        unblock)
            COMPREPLY=( $(compgen -W "-f --force -q --quiet" -- ${cur}) )
            return 0
            ;;
        schedule)
            COMPREPLY=( $(compgen -W "show setup remove" -- ${cur}) )
            return 0
            ;;
        -p|--profile)
            local profiles=$(ls ~/.config/stopbrowsing/profiles/*.yaml 2>/dev/null | xargs -I {} basename {} .yaml)
            COMPREPLY=( $(compgen -W "${profiles}" -- ${cur}) )
            return 0
            ;;
    esac
}

complete -F _stopbrowsing stopbrowsing
EOF
    
    print_success "Shell completion installed"
    print_status "Restart your shell or run: source ~/.bashrc"
}

# Create desktop entry
create_desktop_entry() {
    print_status "Creating desktop entry..."
    
    local desktop_dir="$HOME/.local/share/applications"
    mkdir -p "$desktop_dir"
    
    cat > "$desktop_dir/stopbrowsing.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=StopBrowsing
Comment=Website blocker for productivity
Exec=gnome-terminal -- stopbrowsing status
Icon=security-high
Terminal=true
Categories=Utility;
Keywords=blocker;productivity;websites;
EOF
    
    print_success "Desktop entry created"
}

# Uninstall function
uninstall() {
    print_status "Uninstalling StopBrowsing..."
    
    # Remove symlink
    sudo rm -f "$INSTALL_DIR/stopbrowsing"
    
    # Remove systemd service
    sudo rm -f "/etc/systemd/system/stopbrowsing.service"
    sudo systemctl daemon-reload
    
    # Remove completion
    rm -f "$HOME/.local/share/bash-completion/completions/stopbrowsing"
    
    # Remove desktop entry
    rm -f "$HOME/.local/share/applications/stopbrowsing.desktop"
    
    print_success "StopBrowsing uninstalled"
    print_warning "Configuration files in $CONFIG_DIR were preserved"
}

# Show usage
usage() {
    cat << EOF
StopBrowsing Installation Script

Usage: $0 [OPTION]

Options:
    install     Install StopBrowsing (default)
    uninstall   Remove StopBrowsing installation
    --help      Show this help message

EOF
}

# Main installation function
main_install() {
    echo "====================================="
    echo "   StopBrowsing Installation Script  "
    echo "====================================="
    echo
    
    check_requirements
    install_script
    setup_config
    install_systemd_service
    setup_completion
    create_desktop_entry
    
    echo
    print_success "Installation completed successfully!"
    echo
    print_status "Next steps:"
    echo "  1. Test installation: stopbrowsing --help"
    echo "  2. Configure profiles: edit ~/.config/stopbrowsing/profiles/"
    echo "  3. Start blocking: stopbrowsing block"
    echo
    print_status "For documentation, see: $SCRIPT_DIR/README.md"
}

# Main script logic
case "${1:-install}" in
    install)
        main_install
        ;;
    uninstall)
        uninstall
        ;;
    --help|-h)
        usage
        ;;
    *)
        print_error "Unknown option: $1"
        usage
        exit 1
        ;;
esac