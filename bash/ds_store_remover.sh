#!/usr/bin/env bash
# Scans for .DS_Store files in any given path. If there are any, it removes them and logs the actions.
# I know this can be done with a single 'find'. I wanted a way to log all the deleted files, in case I need it later on.
# Author: Lars Eissink

# Variables
FILEPATH="/path/to/files"
LOGFILE="/path/to/script/remove.log"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOGFILE"
}

# Script start
echo "--- NEW RUN STARTED AT: $(date '+%Y-%m-%d %H:%M:%S') ---" | tee -a "$LOGFILE"
log "Starting .DS_Store cleanup..."

# Validity check
if [[ ! -d "$FILEPATH" ]]; then
    log "ERROR: Provided path '$FILEPATH' is not a directory or does not exist."
    exit 2
fi

# Find files
log "Scanning directory: $FILEPATH"
mapfile -d '' FILES < <(find "$FILEPATH" -type f -iname '.DS_Store' -print0)

if (( ${#FILES[@]} == 0 )); then
    log "No .DS_Store files found."
    exit 1
fi

log "Found ${#FILES[@]} .DS_Store file(s). Removing..."

count=0
for file in "${FILES[@]}"; do
    if [[ -f "$file" ]]; then
        log "Removing: $file"
        rm -f "$file"
        ((count++))
    fi
done

log "Cleanup complete. Total files removed: $count"
exit 0
