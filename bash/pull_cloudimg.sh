#!/bin/bash
# Author: Lars Eissink
# https://github.com/Larse99
# This script pulls CloudImages from various distribution. The script performs a integrity check as well.
# Also included emojis, for once lol.

set -e

declare -A IMAGE_URLS=(
  [debian]="https://cloud.debian.org/images/cloud/bookworm/daily/latest/debian-12-genericcloud-amd64-daily.qcow2"
  [ubuntu]="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  [rocky]=""
  [almalinux]=""
)

download_dir=""

# Function to download and verify a image
download_image() {
  local distro="$1"
  local url="${IMAGE_URLS[$distro]}"
  local filename="${url##*/}"
  local filepath="$download_dir/$filename"
  local checksumfile="$filepath.sha256"

  mkdir -p "$download_dir"

  echo "Chosen distro: $distro"
  echo "Download URL: $url"
  echo "Filename: $filename"

  if [[ -f "$filepath" && -f "$checksumfile" ]]; then
    echo "File and checksum exist... Checking integrity..."
    if sha256sum -c "$checksumfile" >/dev/null 2>&1; then
      echo "✅ Checksum OK. Download will be skipped."
      return 0
    else
      echo "❌ Checksum mismatch — Image will be downloaded."
      rm -f "$filepath"
    fi
  elif [[ -f "$filepath" && ! -f "$checksumfile" ]]; then
    echo "No Checksum found. Generating a new checksum"
    sha256sum "$filepath" > "$checksumfile"
    echo "✅ Checksum generated. This will be used next time"
    return 0
  fi

  echo "⬇️ Downloading.."
  curl -L "$url" -o "$filepath"

  echo "🔐 Generating checksum file..."
  sha256sum "$filepath" > "$checksumfile"
  echo "✅ Download and Checksum finished."
}

# Show menu, if no option was given
show_menu() {
  echo "Which image do you want to download?"
  select distro in "${!IMAGE_URLS[@]}"; do
    if [[ -n "$distro" ]]; then
      download_image "$distro"
      break
    else
      echo "Invalid! Please try again.."
    fi
  done
}

# Main logic
main() {
  if [[ -n "$1" ]]; then
    distro_input="$1"
    if [[ -n "${IMAGE_URLS[$distro_input]}" ]]; then
      download_image "$distro_input"
    else
      echo "Unknown distribution: $distro_input"
      echo "Available choices: ${!IMAGE_URLS[@]}"
      exit 1
    fi
  else
    show_menu
  fi
}

main "$@"
