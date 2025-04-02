#!/usr/bin/bash
# Creates a backup of a remote webserver
# Author: Lars Eissink

# Variables - change these if needed.
REMOTE_USER=""
REMOTE_HOST=""
WEBDATA_PATH=""
NGINX_PATH="/etc/nginx"
HAPROXY_PATH="/etc/haproxy"
LOCAL_BACKUP_DIR=""
TAR_NAME="backup-$(date +%F).tar.gz"
LOG_FILE="$LOCAL_BACKUP_DIR/backup.log"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# Function to check exit status
check_exit() {
    if [ $? -ne 0 ]; then
        log "ERROR: $1"
        exit 1
    fi
}

echo "--- NEW RUN STARTED AT: $(date '+%Y-%m-%d %H:%M:%S') ---" | tee -a "$LOG_FILE"
log "Starting backup..."

# Create a new backup directory
BACKUP_TMP_DIR="$LOCAL_BACKUP_DIR/tmp-$(date +%F)"
mkdir -p "$BACKUP_TMP_DIR/webdata" "$BACKUP_TMP_DIR/config"
check_exit "Failed to create backup directories."

# Rsync content from remote server to newly created directory
log "Syncing webdata..."
rsync -az ${REMOTE_USER}@${REMOTE_HOST}:${WEBDATA_PATH}/ "$BACKUP_TMP_DIR/webdata/" >> "$LOG_FILE" 2>&1
check_exit "Failed to sync webdata."

log "Syncing NGINX config..."
rsync -az ${REMOTE_USER}@${REMOTE_HOST}:${NGINX_PATH} "$BACKUP_TMP_DIR/config/" >> "$LOG_FILE" 2>&1
check_exit "Failed to sync NGINX config."

log "Syncing HAProxy config..."
rsync -az ${REMOTE_USER}@${REMOTE_HOST}:${HAPROXY_PATH} "$BACKUP_TMP_DIR/config/" >> "$LOG_FILE" 2>&1
check_exit "Failed to sync HAProxy config."

# TAR the newly created backup
log "Creating archive $TAR_NAME..."
tar -czf "$LOCAL_BACKUP_DIR/$TAR_NAME" -C "$LOCAL_BACKUP_DIR" "tmp-$(date +%F)" >> "$LOG_FILE" 2>&1
check_exit "Failed to create tar archive."

# Set ownership and permissions
log "Setting file permissions..."
chown admin: "$LOCAL_BACKUP_DIR/$TAR_NAME"
chmod 0600 "$LOCAL_BACKUP_DIR/$TAR_NAME"

# Remove the tmp directory
rm -rf "$BACKUP_TMP_DIR"
log "Backup completed successfully."

# Retention: Keep only the last 14 backups
log "Checking backup retention..."
find "$LOCAL_BACKUP_DIR" -maxdepth 1 -type f -name "backup-*.tar.gz" | sort | head -n -14 | while read -r old_backup; do
    log "Deleting old backup: $old_backup"
    rm -f "$old_backup"
done

log "Backup process finished."
exit 0
