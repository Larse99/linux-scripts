#!/bin/bash
# Measures the Time to first byte of a website
# Usage: ttfb.sh <domain>
# Author: Lars Eissink
# https://github.com/Larse99

# Color Codes
# Normal
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\e[0;35m'
WHITE='\e[1;37m'
BBLUE="\e[1;34m" # Bold blue
R='\033[0m' # Reset all coloring

### Functions ###
show_help() {
    echo -e "${WHITE}TTFB Calculator Help${R}"

    echo -e "${WHITE}Usage:${R}"
    echo -e "  ${GREEN}ttfb${R} ${YELLOW}[options]${R} ${CYAN}<url>${R}"
    echo
    echo -e "${WHITE}Options:${R}"
    echo -e "  ${YELLOW}-e${R}      Show ${CYAN}extended${R} information (DNS, SSL, redirects, HTTP version)"
    echo -e "  ${YELLOW}-h${R}      Show this help message"
    echo
    echo -e "${WHITE}Examples:${R}"
    echo -e "  ${GREEN}ttfb${R} https://example.com"
    echo -e "  ${GREEN}ttfb${R} ${YELLOW}-e${R} https://example.com"
    echo
    echo -e "${WHITE}Info:${R}"
    echo -e "  Calculates connection time, TTFB, and total time using curl."
    echo -e "  Extended mode adds DNS lookup, SSL handshake time, redirects and more."
    echo
}

### Parse arguments ###
# Reset options
extended=0

while getopts "h?e" opt; do
    case "$opt" in
        h|\?)
            show_help
            exit 0
            ;;

        e) extended=1
        ;;
    esac
done
shift $((OPTIND - 1))

# Check if given URL is valid ($1)
if [ -z "$1" ]; then
    echo -e "${RED}Error:${R} no domain specified."
    echo "Example: $0 https://example.com"
    exit 1
fi

# Check if given URL contains either http:// or https://
if [[ "$1" != http://* && "$1" != https://* ]]; then
    echo -e "${RED}Error:${R} URL must start with http:// or https://"
    exit 1
fi

# Save URL as variable, for readabilty.
URL=$1

### Main logic ###
# cURL standard measuring
output=$(curl -o /dev/null -s -w "%{time_connect} %{time_starttransfer} %{time_total}" -H 'Cache-Control: no-cache' "$URL")
connect_time=$(echo "$output" | awk '{print $1}')
ttfb=$(echo "$output" | awk '{print $2}')
total_time=$(echo "$output" | awk '{print $3}')

# Color function + rounding
colorize_time() {
    local time=$1
    local rounded
    rounded=$(printf "%.3f" "$time")
    if (( $(echo "$rounded < 0.3" | bc -l) )); then
        echo -e "${GREEN}${rounded} sec${R}"
    elif (( $(echo "$rounded < 1.0" | bc -l) )); then
        echo -e "${YELLOW}${rounded} sec${R}"
    else
        echo -e "${RED}${rounded} sec${R}"
    fi
}

# Always show basic information
echo -e "URL: ${YELLOW}$URL${R}\n"
echo -e "${BBLUE}TTFB information${R}"
echo -e "${WHITE}Connection Time    ${R}: $(colorize_time "$connect_time")"
echo -e "${WHITE}Time to First Byte ${R}: $(colorize_time "$ttfb")"
echo -e "${WHITE}Total Time         ${R}: $(colorize_time "$total_time")"

# Extended information, if -e has been given.
if [ "$extended" = 1 ]; then
    echo
    echo -e "${BBLUE}Extended information${R}"

    # Get IP-address
    host=$(echo "$URL" | awk -F/ '{print $3}')
    IP=$(dig +short "$host" | head -n 1)
    echo -e "${WHITE}Resolved IP          ${R}: ${IP:-Unavailable}"

    # Get cURL timing information
    extended_output=$(curl -o /dev/null -s -w "%{time_namelookup} %{time_connect} %{time_appconnect} %{http_code} %{http_version}" "$URL")
    dns_lookup=$(echo "$extended_output" | awk '{print $1}')
    tcp_connect=$(echo "$extended_output" | awk '{print $2}')
    ssl_handshake=$(echo "$extended_output" | awk '{print $3}')
    http_code=$(echo "$extended_output" | awk '{print $4}')
    http_version=$(echo "$extended_output" | awk '{print $5}')

    # Print extended information
    echo -e "${WHITE}DNS Lookup Time      ${R}: $(colorize_time "$dns_lookup")"
    echo -e "${WHITE}TCP Connect Time     ${R}: $(colorize_time "$tcp_connect")"
    echo -e "${WHITE}SSL Handshake Time   ${R}: $(colorize_time "$ssl_handshake")"
    echo -e "${WHITE}HTTP Status Code     ${R}: ${http_code}"
    echo -e "${WHITE}HTTP Version         ${R}: ${http_version}"

    # Redirects
    redirects=$(curl -s -L -I "$URL" | grep -i "^location:" | wc -l)
    echo -e "${WHITE}Redirects            ${R}: $redirects"
fi
