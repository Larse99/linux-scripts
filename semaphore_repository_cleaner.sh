#!/bin/bash
# Author: Lars Eissink

# Settings
PBPATH=""
LOGPATH=""

# Search directories
DIRS=$(find "${PBPATH}" -maxdepth 1 \( -name '*inventory*' -o -name '*repository*' \))
DATE=$(date '+%d-%m-%Y %H:%M:%S')

# Start new run
echo "NEW RUN STARTED AT: ${DATE}" | tee -a "$LOGPATH"

# Check if there are any new directories
if [[ -z "$DIRS" ]]; then
    echo "[$DATE] No directories found to remove." | tee -a "$LOGPATH"
else
    # Calculate current / old size
    OLD_SIZE=$(du -sm ${DIRS} 2>/dev/null | awk '{sum += $1} END {print sum}')

    # Loop through the directories and remove them
    for dir in $DIRS; do
        DATE=$(date '+%d-%m-%Y %H:%M:%S')
        echo "[$DATE] Deleting: $dir" | tee -a "$LOGPATH"
        rm -rf "$dir"
    done

    # Calculate new size
    NEW_SIZE=$(du -sm ${PBPATH} 2>/dev/null | awk '{sum += $1} END {print sum}')

    # Calculate MBs freed
    FREED_MB=$((OLD_SIZE - NEW_SIZE))
    ((FREED_MB < 0)) && FREED_MB=0

    # Log the result
    DATE=$(date '+%d-%m-%Y %H:%M:%S')
    echo "[$DATE] Disk space saved: ${FREED_MB} MB" | tee -a "$LOGPATH"
fi

# Add empty line for readability
echo "" | tee -a "$LOGPATH"
