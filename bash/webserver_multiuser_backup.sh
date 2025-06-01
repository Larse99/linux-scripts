#!/usr/bin/env bash
# Modular backup script for webserver
# Author: Lars Eissink

REMOTE_USER="user"
REMOTE_HOST="hostname.fqdn"
LOCAL_BACKUP_BASE="/mnt/mybackups"
LOG_FILE="$LOCAL_BACKUP_BASE/backup.log"
USERS=("add" "users" "here")
TODAY=$(date +%F)
RETENTION=10

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

log "--- NEW RUN STARTED AT: $(date '+%Y-%m-%d %H:%M:%S') ---"
log "Starting backup process..."

for user in "${USERS[@]}"; do
    log "Backing up web data for user: $user"

    REMOTE_PATH="/home/${user}/domains"
    USER_BACKUP_DIR="${LOCAL_BACKUP_BASE}/${user}"
    TMP_DIR="${USER_BACKUP_DIR}/${user}-${TODAY}"
    TAR_NAME="${user}-backup-${TODAY}.tar.gz"

    mkdir -p "$TMP_DIR" || {
        log "ERROR: Failed to create temp directory for user $user. Skipping..."
        continue
    }

    log "Syncing web data for $user..."
    rsync -az "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/" "$TMP_DIR/" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to sync web data for user $user. Skipping..."
        rm -rf "$TMP_DIR"
        continue
    fi

    log "Creating archive $TAR_NAME for $user..."
    tar -czf "${USER_BACKUP_DIR}/${TAR_NAME}" -C "$USER_BACKUP_DIR" "${user}-${TODAY}" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to create tar archive for user $user. Skipping..."
        rm -rf "$TMP_DIR"
        continue
    fi

    chown admin: "${USER_BACKUP_DIR}/${TAR_NAME}"
    chmod 0600 "${USER_BACKUP_DIR}/${TAR_NAME}"
    rm -rf "$TMP_DIR"
    log "Web data backup for $user completed."

    # Retention policy
    log "Applying retention policy for $user..."
    find "$USER_BACKUP_DIR" -maxdepth 1 -type f -name "${user}-backup-*.tar.gz" | sort | head -n -$RETENTION | while read -r old_backup; do
        log "Deleting old backup for $user: $old_backup"
        rm -f "$old_backup"
    done
done

# --- Shared config backup ---

log "Backing up server configuration..."

# Paths to backup
CONFIG_PATHS=(
    "/etc/nginx"
    "/etc/haproxy"
)

SERVER_BACKUP_DIR="${LOCAL_BACKUP_BASE}/webserverConfigs"
TMP_CONFIG_DIR="${SERVER_BACKUP_DIR}/${TODAY}"
TAR_NAME="server-config-backup-${TODAY}.tar.gz"

mkdir -p "$TMP_CONFIG_DIR" || {
    log "ERROR: Failed to create temp config directory. Skipping config backup."
    exit 1
}

for path in "${CONFIG_PATHS[@]}"; do
    log "Syncing ${path}..."
    rsync -az "${REMOTE_USER}@${REMOTE_HOST}:${path}" "$TMP_CONFIG_DIR/" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to sync $path. Skipping..."
        continue
    fi
done

log "Creating config archive $TAR_NAME..."
tar -czf "${SERVER_BACKUP_DIR}/${TAR_NAME}" -C "$SERVER_BACKUP_DIR" "${TODAY}" >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
    log "ERROR: Failed to create config tar archive"
    rm -rf "$TMP_CONFIG_DIR"
    exit 1
fi

chown admin: "${SERVER_BACKUP_DIR}/${TAR_NAME}"
chmod 0600 "${SERVER_BACKUP_DIR}/${TAR_NAME}"
rm -rf "$TMP_CONFIG_DIR"
log "Server config backup completed."

log "Applying retention policy for server config..."
find "$SERVER_BACKUP_DIR" -maxdepth 1 -type f -name "server-config-backup-*.tar.gz" | sort | head -n -14 | while read -r old_backup; do
    log "Deleting old config backup: $old_backup"
    rm -f "$old_backup"
done

log "Backup process finished successfully."
exit 0
