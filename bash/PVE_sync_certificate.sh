#!/bin/bash
# Proxmox refreshSSL
#
# Synopsis:
# Renews the Proxmox PVE certificate of the WebUI with one saved on a public facing server.
# Ideal if you have your Lets Encrypt certificates on a different server, and you need to replace the certificates
# every three months. Just create a cron and this script does it for you.
# 
# Author: Lars Eissink
# Git: https://github.com/Larse99

set -euo pipefail

# ---- Configuration ----

# SSL certificate settings
DEST_DIR="/etc/pve/nodes/<NODE_NAME>"
DEST_KEYNAME="pveproxy-ssl.key"
DEST_CERTNAME="pveproxy-ssl.pem"

# SSH / RSync settings
REMOTE_HOST="lb1.yourdomain.tld" # The host where the certificate is saved
REMOTE_USER="root" # Remote user
REMOTE_PATH="/etc/letsencrypt/live/<DOMAIN>" # Path to the certificate
REMOTE_CERTNAME="fullchain.pem" # Certificate name
REMOTE_KEYNAME="privkey.pem" # Name of the privatekey


# ---- Functions ----
log() {
    # Green "[INFO]" label
    printf "\033[1;32m[INFO]\033[0m %s\n" "$*"
}

error_exit() {
    printf "\033[1;31m[ERROR]\033[0m %s\n" "$*" >&2
    exit 1
}

rsync_file() {
    local src_file="$1"
    local dest_file="$2"

    log "Syncing $(basename "$src_file") → $(basename "$dest_file")"
    rsync -L --inplace \
        "$REMOTE_USER@$REMOTE_HOST:$src_file" \
        "$dest_file" || error_exit "Failed to sync $src_file"
}

# ---- Main Logic ----

# Check if DEST_DIR is writable
[[ -w "$DEST_DIR" ]] || error_exit "Destination directory '$DEST_DIR' is not writable."

# Rsync certificate
rsync_file "$REMOTE_PATH/$REMOTE_CERTNAME" "$DEST_DIR/$DEST_CERTNAME"

# Rsync key
rsync_file "$REMOTE_PATH/$REMOTE_KEYNAME" "$DEST_DIR/$DEST_KEYNAME"

# Change permissions
log "Changing permissions to 640..."
chmod 640 "$DEST_DIR/$DEST_KEYNAME" "$DEST_DIR/$DEST_CERTNAME"

# Restart PVEProxy
log "Restarting PVEProxy..."
systemctl restart pveproxy

log "SSL certificate update completed successfully."
