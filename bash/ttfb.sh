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

# Bold
BBLUE="\e[1;34m"

R='\033[0m' # reset

# Check if given URL is valid
if [ -z "$1" ]; then
    echo -e "${RED}Error:${R} no domain specified."
    echo "Example:: $0 https://example.com"
    exit 1
fi

# Perform a cURL and save the output to variables
output=$(curl -o /dev/null -s -w "%{time_connect} %{time_starttransfer} %{time_total}" -H 'Cache-Control: no-cache' "$1")
connect_time=$(echo "$output" | awk '{print $1}')
ttfb=$(echo "$output" | awk '{print $2}')
total_time=$(echo "$output" | awk '{print $3}')

# Function to calculate color based on output time. This does also some rounding.
colorize_time() {
    local time=$1
    local rounded
    rounded=$(printf "%.3f" "$time")  # Limit to 3 decimal places
    if (( $(echo "$rounded < 0.3" | bc -l) )); then
        echo -e "${GREEN}${rounded} sec${R}"
    elif (( $(echo "$rounded < 1.0" | bc -l) )); then
        echo -e "${YELLOW}${rounded} sec${R}"
    else
        echo -e "${RED}${rounded} sec${R}"
    fi
}

# Output!
echo -e "URL: ${YELLOW}$1${R}\n"
echo -e "${BBLUE}TTFB information${R}" 
echo -e "${WHITE}Connection Time    ${R}: $(colorize_time "$connect_time")"
echo -e "${WHITE}Time to First Byte ${R}: $(colorize_time "$ttfb")"
echo -e "${WHITE}Total Time         ${R}: $(colorize_time "$total_time")"

echo -e "\nMore information will be added later. ... Probably."