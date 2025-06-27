#!/bin/bash
# Checks if a page has been accessed and sends a PushOver if so
# The script utilizes the free ipwho.is API, to get certain information about a IP
# Optional: Create a systemd service to start, stop and enable this script
# Made purely for fun lol
# Author: Lars Eissink
# https://github.com/Larse99

# Variables - Change these
NGINX_LOG="" # Important: the NGINX logfile to check.
LOGFILE="" # Logfile. The place where the script logs additional information.
PO_APIKEY="" # Your PushOver API key
PO_USERKEY="" # Your PushOver User key
REPORTED_ENTRIES="reported.cache" # Cache file to store requests that already have been checked

### Functions
# Simple logging function
log() {
        echo -e "$1" | tee -a "$LOGFILE"
}

# Send Pushover notification
sendNotification() {
    message="$1"
    curl -s \
        -F "token=$PO_APIKEY" \
        -F "user=$PO_USERKEY" \
        --form-string "message=$message" \
        https://api.pushover.net/1/messages.json > /dev/null
}

# Gets information about a given IP
getInfoFromIP() {
    ip="$1"
    data=$(curl -s "https://ipwho.is/$ip")

    # Check if request was successful
    success=$(echo "$data" | jq -r '.success')
    if [[ "$success" != "true" ]]; then
        echo -e "$ip\t[no data]"
        return
    fi

    # Parse IP info
    country=$(echo "$data" | jq -r '.country')
    city=$(echo "$data" | jq -r '.city')
    asn=$(echo "$data" | jq -r '.connection.asn')
    isp=$(echo "$data" | jq -r '.connection.isp')
    domain=$(echo "$data" | jq -r '.connection.domain')

    log "IP Information:\t$ip\t$country\t$city\t$asn\t$isp\t$domain"
}

# Checks the log for a required string and handles reporting
checkLog() {
    log_file="$1"
    required_string="$2"

    if [[ ! -f $log_file ]]; then
        echo "ERROR: $log_file does not exist."
        exit 2
    fi

    # Create cache file if it does not exist
    touch "$REPORTED_ENTRIES"

    grep -- "$required_string.*200" "$log_file" | grep -vi 'favicon.ico' | while read -r line; do
        # Extract fields
        ip=$(echo "$line" | awk '{ print $1 }' | sed 's/^::ffff://')
        useragent=$(echo "$line" | sed -n 's/.*"\(Mozilla[^"]*\)".*/\1/p')
        time=$(echo "$line" | awk '{ print $4 }' | tr -d "[")
        request=$(echo "$line" | awk '{ print $6, $7 }' | tr -d '"')
        referer=$(echo "$line" | awk '{ print $11 }' | tr -d '"')

        # Create unique fingerprint for deduplication
        fingerprint="${time}_${ip}_${request}"

        # Skip if already reported
        if grep -qF "$fingerprint" "$REPORTED_ENTRIES"; then
            continue
        fi

        # Print details
        log "Time:\t\t$time"
        getInfoFromIP "$ip"
        log "Useragent:\t$useragent"
        log "Request:\t$request"
        log "Referer:\t$referer"
        log "--------------------------\n"

        # Send notification
        msg="Page accessed:
        IP: $ip
        Time: $time
        Request: $request
        "
        sendNotification "$msg"

        # Store fingerprint
        echo "$fingerprint" >> "$REPORTED_ENTRIES"
    done
}

# Main logic
# Add a loop, so it doesn't quit
while true; do
        checkLog "$NGINX_LOG" "uri_to_check.php"
        sleep 600
done
