#!/usr/bin/bash
# Backup Script for Vaultwarden
# Author: Lars Eissink
# 2025

# Variables - Change these, if needed.
# Authentication
REMOTE_USER="root"
REMOTE_HOST="remote.prod.host.tld"
LOCAL_USER=""

# Docker information
DOCKER_CT_NAME=""

# Paths
VW_DATA_PATH=""
LOCAL_BACKUP_DIR=""
LOG_FILE="$LOCAL_BACKUP_DIR/vaultwarden.log"
TAR_NAME="vaultwarden-backup-$(date +%F).tar.gz"

# -- Do not edit below here --
# Functions

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# Check exit code
check_exit() {
    if [ $? -ne 0 ]; then
        log "ERROR: $1"
        exit 1
    fi
}

# Main execution
echo "--- NEW RUN STARTED AT: $(date '+%Y-%m-%d %H:%M:%S') ---" | tee -a "$LOG_FILE"
log "Starting backup..."

# Create a new temporary backup directory
BACKUP_TMP_DIR="$LOCAL_BACKUP_DIR/tmp-$(date +%F)"
mkdir -p $BACKUP_TMP_DIR
check_exit "Failed to create backup directories."

# Stop Vaultwarden remote container
log "Stopping Vaultwarden container"
ssh $REMOTE_USER@$REMOTE_HOST docker stop $DOCKER_CT_NAME
check_exit "Failed to stop Docker Container."

# Rsync remote content from remote server to temporary directory
log "Syncing Vaultwarden data..."
rsync -az ${REMOTE_USER}@${REMOTE_HOST}:${VW_DATA_PATH}/ "$BACKUP_TMP_DIR/data" >> "$LOG_FILE" 2>&1
check_exit "Failed to sync data from remote host."

# TAR the newly created backup
log "Creating archive $TAR_NAME..."
tar -czf "$LOCAL_BACKUP_DIR/$TAR_NAME" -C "$LOCAL_BACKUP_DIR" "tmp-$(date +%F)" >> "$LOG_FILE" 2>&1
check_exit "Failed to create tar archive."

# Set ownership and permissions
log "Setting file permissions..."
chown $LOCAL_USER: "$LOCAL_BACKUP_DIR/$TAR_NAME"
chmod 0600 "$LOCAL_BACKUP_DIR/$TAR_NAME"

# Remove the tmp directory
rm -rf "$BACKUP_TMP_DIR"
log "Backup completed successfully."

# Start Vaultwarden remote container
log "Starting Vaultwarden container..."
ssh $REMOTE_USER@$REMOTE_HOST docker start $DOCKER_CT_NAME
check_exit "Failed to start Vaultwarden container."

# Retention: Keep only the last 14 backups
log "Checking backup retention..."
find "$LOCAL_BACKUP_DIR" -maxdepth 1 -type f -name "vaultwarden-backup-*.tar.gz" | sort | head -n -14 | while read -r old_backup; do
    log "Deleting old backup: $old_backup"
    rm -f "$old_backup"
done

log "Backup process finished."
exit 0
