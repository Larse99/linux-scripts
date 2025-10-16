#!/bin/bash
# Author: Lars Eissink
# Updates POrtainer images and redeploys if there is an update
# There are better ways to do this, but this way I can manage it with Semaphore.

set -ueo pipefail

# Configuration
podman=$(command -v podman)
compose="/path/to/composefile.yml"
service="container_name"

# Functions
log () {
        echo -e "[$(date '+%d-%m-%Y %H:%M:%S')] $*"
}

# Checks
if [[ -z "$podman" ]]; then
        echo "Error: Podman is not found in PATH." >&2
        exit 1
fi

if [[ ! -f "$compose" ]]; then
        echo "Error: Compose file not found at $compose" >&2
fi

# Get digest -> This is needed so we can check if there is a new image
log "Getting current image digest..."
currentImage=$($podman ps --filter "name=${service}" --format "{{.Image}}")

if [[ -z "$currentImage"  ]]; then
        echo "Error: Could not find running container: ${service}" >&2
        exit 1
fi

currentDigest=$($podman inspect "$currentImage" 2>/dev/null | grep -m1 Digest | awk -F '"' '{ print $4 }' || true)
log "Current digest: ${currentDigest}"

# Pull new image
log "Pulling new image..."
$podman compose -f "$compose" pull

# Get new digest
newDigest=$($podman inspect "$currentImage" 2>/dev/null | grep -m1 '"Digest"' | awk -F '"' '{print $4}' || true)
log "New digest: ${newDigest:-unknown}"

# Compare digests
if [[ "$currentDigest" != "$newDigest" && -n "$newDigest" ]]; then
        log "New image detected, restarting container..."
        $podman compose -f "$compose" down
        $podman compose -f "$compose" up -d
        log "Portainer restarted with updated image."
else
        log "No update available. Portainer is up-to-date"
fi

log "Done."