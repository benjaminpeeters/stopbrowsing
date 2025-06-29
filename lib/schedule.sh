#!/bin/bash

# Scheduling system for stopbrowsing

SCHEDULE_FILE="/tmp/stopbrowsing.schedule"
UNBLOCK_FILE="/tmp/stopbrowsing.unblock.at"

# Schedule temporary unblock
schedule_unblock() {
    local duration_minutes="$1"
    local unblock_time=$(date -d "+${duration_minutes} minutes" "+%Y-%m-%d %H:%M:%S")
    
    # Store unblock time
    echo "$unblock_time" > "$UNBLOCK_FILE"
    
    # Create at job for unblocking
    if command -v at >/dev/null 2>&1; then
        echo "$SCRIPT_DIR/stopbrowsing.sh unblock -q" | at "now + $duration_minutes minutes" 2>/dev/null
    else
        # Fallback: use cron-like approach with sleep
        (
            sleep $((duration_minutes * 60))
            "$SCRIPT_DIR/stopbrowsing.sh" unblock -q
            rm -f "$UNBLOCK_FILE"
        ) &
    fi
}

# Cancel scheduled unblock
cancel_scheduled_unblock() {
    # Remove unblock file
    rm -f "$UNBLOCK_FILE"
    
    # Cancel at jobs (best effort)
    if command -v atq >/dev/null 2>&1 && command -v atrm >/dev/null 2>&1; then
        atq | grep "stopbrowsing.sh unblock" | awk '{print $1}' | xargs -r atrm 2>/dev/null
    fi
}

# Set up recurring schedule
setup_schedule() {
    local work_hours="${CONFIG[schedule_work_hours]:-09:00-17:00}"
    local work_days="${CONFIG[schedule_work_days]:-Mon-Fri}"
    
    if [[ "${CONFIG[schedule_enabled]}" != "true" ]]; then
        return 0
    fi
    
    # Parse work hours
    local start_time="${work_hours%-*}"
    local end_time="${work_hours#*-}"
    
    # Convert days to cron format
    local cron_days
    case "$work_days" in
        "Mon-Fri") cron_days="1-5" ;;
        "Mon-Sat") cron_days="1-6" ;;
        "Mon-Sun") cron_days="0-6" ;;
        *) cron_days="1-5" ;;
    esac
    
    # Parse start time
    local start_hour="${start_time%:*}"
    local start_min="${start_time#*:}"
    
    # Parse end time
    local end_hour="${end_time%:*}"
    local end_min="${end_time#*:}"
    
    # Add cron jobs
    local crontab_content
    crontab_content=$(crontab -l 2>/dev/null | grep -v "stopbrowsing")
    
    # Add block job
    crontab_content+="\n$start_min $start_hour * * $cron_days $SCRIPT_DIR/stopbrowsing.sh block -q"
    
    # Add unblock job
    crontab_content+="\n$end_min $end_hour * * $cron_days $SCRIPT_DIR/stopbrowsing.sh unblock -q"
    
    # Install new crontab
    echo -e "$crontab_content" | crontab -
    
    echo "Schedule installed:"
    echo "  Block: $start_time on $work_days"
    echo "  Unblock: $end_time on $work_days"
}

# Remove schedule
remove_schedule() {
    # Remove cron jobs
    crontab -l 2>/dev/null | grep -v "stopbrowsing" | crontab -
    
    # Cancel any pending jobs
    cancel_scheduled_unblock
    
    echo "Schedule removed"
}

# Show current schedule
show_schedule() {
    echo "Current schedule configuration:"
    echo "  Enabled: ${CONFIG[schedule_enabled]:-false}"
    echo "  Work hours: ${CONFIG[schedule_work_hours]:-09:00-17:00}"
    echo "  Work days: ${CONFIG[schedule_work_days]:-Mon-Fri}"
    echo ""
    
    # Show active cron jobs
    local cron_jobs
    cron_jobs=$(crontab -l 2>/dev/null | grep "stopbrowsing")
    
    if [[ -n "$cron_jobs" ]]; then
        echo "Active scheduled jobs:"
        echo "$cron_jobs" | sed 's/^/  /'
    else
        echo "No scheduled jobs found"
    fi
    
    # Show pending unblock
    if [[ -f "$UNBLOCK_FILE" ]]; then
        local unblock_time=$(cat "$UNBLOCK_FILE")
        echo ""
        echo "Pending unblock: $unblock_time"
    fi
}

# Command: schedule
cmd_schedule() {
    local action="${1:-show}"
    
    case "$action" in
        show)
            show_schedule
            ;;
        setup|install)
            setup_schedule
            ;;
        remove|disable)
            remove_schedule
            ;;
        *)
            echo "Usage: $(basename "$0") schedule [show|setup|remove]"
            return 1
            ;;
    esac
}