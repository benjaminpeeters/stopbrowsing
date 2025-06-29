# StopBrowsing

A powerful, modular website blocker for Linux that helps boost productivity by blocking distracting websites at the system level.

## Features

- **System-level blocking** using `/etc/hosts` file modification
- **DNS-over-HTTPS (DoH) blocking** to prevent browser DNS bypass
- **Multiple profiles** for different scenarios (work, minimal, custom)
- **Temporary blocking** with automatic unblocking after specified time
- **Scheduled blocking** with cron integration
- **DNS cache flushing** for immediate effect
- **Desktop notifications** for blocking/unblocking events
- **Connection termination** for existing connections to blocked sites
- **Systemd service** support for system-wide blocking
- **Backup and restore** functionality for hosts file
- **Exception handling** for allowing specific URLs within blocked domains
- **Modular architecture** with clean separation of concerns

## Installation

### Quick Install

```bash
git clone <repository-url> stopbrowsing
cd stopbrowsing
chmod +x stopbrowsing.sh
sudo ln -sf "$(pwd)/stopbrowsing.sh" /usr/local/bin/stopbrowsing
```

### Manual Install

1. Download or clone the repository
2. Make the main script executable: `chmod +x stopbrowsing.sh`
3. Optionally install systemd service: `./stopbrowsing.sh install`

## Usage

### Basic Commands

```bash
# Block websites using default profile
stopbrowsing block

# Block websites using work profile
stopbrowsing block -p work

# Block for 30 minutes (temporary)
stopbrowsing block -t 30

# Unblock all websites
stopbrowsing unblock

# Check current status
stopbrowsing status

# List websites in current profile
stopbrowsing list

# List websites in specific profile
stopbrowsing list work
```

### Managing Websites

```bash
# Add website to default profile
stopbrowsing add youtube.com

# Add website to specific profile
stopbrowsing add reddit.com work

# Remove website from default profile
stopbrowsing remove youtube.com

# Remove website from specific profile
stopbrowsing remove reddit.com work
```

### Scheduling

```bash
# Show current schedule
stopbrowsing schedule

# Setup scheduled blocking (using config file settings)
stopbrowsing schedule setup

# Remove scheduled blocking
stopbrowsing schedule remove
```

## Configuration

### Main Configuration

Configuration is stored in `~/.config/stopbrowsing/config.yaml`. The default configuration includes:

```yaml
# Default profile to use
profile: default

# Enable/disable blocking
enabled: true

# DNS-over-HTTPS blocking to prevent browser bypass
doh_blocking:
  enabled: true # Block DoH requests for blocked websites only

# Notification settings
notifications:
  enabled: true
  sound: false

# DNS settings
dns:
  flush_cache: true

# Schedule settings
schedule:
  enabled: false
  work_hours: "09:00-17:00"
  work_days: "Mon-Fri"

# Statistics tracking
statistics:
  track_success: true
  start_date: "2025-01-01"
```

### Profiles

Website lists are managed through profiles stored in `~/.config/stopbrowsing/profiles/`. Three default profiles are provided:

- **default**: Comprehensive list of social media, video, and gaming sites
- **work**: Stricter blocking including news and shopping sites
- **minimal**: Only the most distracting sites (social media and major video platforms)

### Custom Profiles

Create custom profiles by adding YAML files to the profiles directory:

```yaml
# ~/.config/stopbrowsing/profiles/custom.yaml
websites:
  - example.com
  - www.example.com
  - another-site.org

# Optional: Define exceptions for specific URLs
exceptions:
  - youtube.com/education/*
  - github.com/user/work-repo
```

## Command Reference

### Block Options

- `-p, --profile PROFILE`: Use specific profile (default: default)
- `-t, --time MINUTES`: Block for specified minutes (temporary)
- `-f, --force`: Force action without confirmation
- `-q, --quiet`: Suppress notifications

### Commands

- `block`: Block websites from configuration
- `unblock`: Unblock all websites  
- `status`: Show current blocking status
- `list [PROFILE]`: List configured websites
- `add WEBSITE [PROFILE]`: Add website to blocklist
- `remove WEBSITE [PROFILE]`: Remove website from blocklist
- `schedule [show|setup|remove]`: Manage scheduled blocks
- `install`: Install systemd service
- `help`: Show help message

## System Integration

### Systemd Service

Install the systemd service for system-wide control:

```bash
stopbrowsing install

# Control via systemctl
sudo systemctl start stopbrowsing    # Block websites
sudo systemctl stop stopbrowsing     # Unblock websites
sudo systemctl enable stopbrowsing   # Enable auto-start
```

### Scheduled Blocking

Enable automatic blocking during work hours by editing the configuration:

```yaml
schedule:
  enabled: true
  work_hours: "09:00-17:00"
  work_days: "Mon-Fri"
```

Then setup the schedule:

```bash
stopbrowsing schedule setup
```

## Files and Directories

- `~/.config/stopbrowsing/config.yaml`: Main configuration
- `~/.config/stopbrowsing/profiles/`: Website profile definitions
- `~/.local/share/stopbrowsing/activity.log`: Activity log
- `~/.local/share/stopbrowsing/backups/`: Hosts file backups
- `/etc/hosts`: System hosts file (modified when blocking)

## Troubleshooting

### Websites Still Accessible

1. **DNS-over-HTTPS (DoH) Bypass**: Modern browsers use DoH by default, which can bypass hosts file blocking.
   - **Solution**: Ensure DoH blocking is enabled in config.yaml
   - **Alternative**: Disable DoH in browser settings or restart browser after blocking
   - **Check status**: Use `stopbrowsing status` to verify DoH blocking is active

2. **DNS Caching**: The tool attempts to flush DNS cache automatically. If sites are still accessible, try:
   ```bash
   # Manual DNS flush
   sudo systemctl restart systemd-resolved
   
   # Or restart NetworkManager
   sudo systemctl restart NetworkManager
   ```

3. **Browser Caching**: Restart your browser after blocking/unblocking

4. **Existing Connections**: The tool terminates existing connections, but some may persist. Try:
   ```bash
   # Force close browser and restart
   pkill -f firefox  # or chrome, etc.
   ```

### Permissions Issues

The tool requires `sudo` privileges to modify `/etc/hosts`. Ensure your user is in the `sudo` group.

### Recovery

If the hosts file becomes corrupted, restore from backup:

```bash
# List available backups
ls ~/.local/share/stopbrowsing/backups/

# Restore specific backup
sudo cp ~/.local/share/stopbrowsing/backups/hosts.YYYYMMDD_HHMMSS /etc/hosts
```

## Development

The codebase is modularly organized:

- `stopbrowsing.sh`: Main executable and command dispatcher
- `lib/config.sh`: Configuration and profile management
- `lib/hosts.sh`: Hosts file manipulation and command implementations
- `lib/dns.sh`: DNS cache management and verification
- `lib/notify.sh`: Desktop notification system
- `lib/schedule.sh`: Scheduling and cron integration

## License

This project is licensed under the AGPL-3.0 License.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.