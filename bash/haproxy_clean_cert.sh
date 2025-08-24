#!/bin/bash
# HAProxy clean certs
# This scripts compares the domains in a domains.map file and the certificates on disk.
# If a certificate has been found, but is not mentioned in the domain mapping, it will be removed on disk and in certbot.
# This scripts takes account for wildcard certificates, as long as they're called '*.domainname.com', so with the *.
# 
# Usage:
# haproxy_clean_cert.sh run
#
# Author: Lars Eissink

# --- Settings ---
CERT_DIR="/etc/haproxy/ssl"
DOMAINS_FILE="/etc/haproxy/maps/domains.map"
LOG_FILE="/var/log/haproxy_cert_cleanup.log"

# --- Logging... ---
log() {
    local msg="$*"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    printf "\033[1;32m[INFO]\033[0m %s\n" "$msg"
    echo "[$timestamp] [INFO] $msg" >> "$LOG_FILE"
}

error() {
    local msg="$*"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    printf "\033[1;31m[ERROR]\033[0m %s\n" "$msg"
    echo "[$timestamp] [ERROR] $msg" >> "$LOG_FILE"
}

# --- Functions ---
cleanup_certs() {
    log "Starting certificate cleanup..."

    shopt -s nullglob

    for cert in "$CERT_DIR"/*.pem; do
        [ -e "$cert" ] || continue  # skip if no match

        cert_name=$(basename "$cert" .pem)

        # Skip wildcard certificates
        if [[ "$cert_name" == \*.* ]]; then
            log "Skipping wildcard certificate $cert_name"
            continue
        fi

        # Check if the certificate name exists in the first field of domains.map
        if ! awk '{print $1}' "$DOMAINS_FILE" | grep -Fxq "$cert_name"; then
            log "Removing local certificate $cert..."
            rm "$cert"

            # Check if Certbot has this certificate
            if certbot certificates | grep -q "Certificate Name: $cert_name"; then
                log "Deleting Certbot certificate $cert_name..."
                certbot delete --cert-name "$cert_name" --non-interactive
            else
                log "No Certbot certificate found for $cert_name"
            fi
        fi
    done
}

reload_haproxy() {
    log "Testing HAProxy configuration..."
    if haproxy -c -f /etc/haproxy/haproxy.cfg; then
        log "HAProxy configuration is valid. Reloading HAProxy..."
        systemctl reload haproxy
        log "HAProxy reloaded successfully."
    else
        error "HAProxy configuration test failed! Not reloading."
        exit 1
    fi
}

# --- Main ---
case "$1" in
    run)
        cleanup_certs
        reload_haproxy
        ;;
    *)
        echo "Usage: $0 run"
        exit 1
        ;;
esac
