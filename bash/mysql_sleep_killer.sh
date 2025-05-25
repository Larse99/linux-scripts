#!/bin/bash
# Kills sleep connections in MySQL if they exceed a certain threshold
# Author: Lars Eissink

# Variables - change these if needed.
THRESHOLD=50
MYSQL_USER="root"
LOG_FILE="/root/sleepkiller.log"

# Log function - So we can lateron tell what has been killed.
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# Get current processlist
PROCESSLIST=$(mysql -u "$MYSQL_USER" -e 'SHOW PROCESSLIST;')

# Count how many processes are in 'Sleep' state
SLEEP_COUNT=$(echo "$PROCESSLIST" | awk 'NR > 1 && $5 == "Sleep"' | wc -l)

log "Amount of 'Sleep' processes: $SLEEP_COUNT"

# Check if threshold has been exceeded and if we have to kill a process
if [ "$SLEEP_COUNT" -gt "$THRESHOLD" ]; then
    log "Threshold exceeded ($THRESHOLD). Killing 'Sleep' processes..."

    # Extract and kill each 'Sleep' process by ID
    echo "$PROCESSLIST" | awk 'NR > 1 && $5 == "Sleep" { print $1 }' | while read -r pid; do
        log "Killing process ID: $pid"
        mysql -u "$MYSQL_USER" -e "KILL $pid;"
    done
else
    # Following line is commented out, otherwise the log file gets cluttered.
    # log "Sleeping processes below threshold. No action taken."
    exit 0
fi
