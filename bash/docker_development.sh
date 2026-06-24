#!/bin/bash
# Author: Lars Eissink
# github.com/Larse99
#
# Sometimes, when im 'developing' something in plain HTML, CSS and JavaScript, I like to do this with a NGINX container.
# This script simply creates a NGINX container and loads a directory as volume, so you can develop in real time.
# Really a small little script, but maybe useful for someone?
#
# Just change the variables and use the README below
# ./dev.sh start    - starts the environment
# ./dev.sh stop     - stops the environment
# ./dev.sh destroy  - stops and destroys the environment
# ./dev.sh status   - checks whether the environment is running
# ./dev.sh logs     - shows a log (tail -f) of the environment (ctrl + C to exit)

set -euo pipefail

# Some variables - change if needed
HOSTNAME=$(cat /etc/hostname)
APP_SOURCE="$(pwd)/../app"
CONTAINER_NAME='development_container'
CONTAINER_PORT=9080
CONTAINER_IMAGE='nginx:latest'

# Get the status of the container, empty string if it doesn't exist
get_status() {
  docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || true
}

# Check if docker is installed and the daemon is reachable
check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed (or not in PATH)."
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon is not running (or not reachable)."
    exit 1
  fi
}

# Check if empty argument
if [ $# -eq 0 ]; then
  echo "Usage: start, stop, restart, destroy, status, logs"
  exit 1
fi

check_docker

# Check which argument is given
case "$1" in
  start)

    # Check the status of the container, before we attempt to start it
    STATUS=$(get_status)
    [ "$STATUS" = "running" ] && echo "Container already running..." && exit 0

    # Make sure the source directory we want to mount actually exists
    if [ ! -d "$APP_SOURCE" ]; then
      echo "App source directory not found: $APP_SOURCE"
      exit 1
    fi

    # Make sure the port isn't already taken by something else
    if (exec 3<>"/dev/tcp/127.0.0.1/$CONTAINER_PORT") 2>/dev/null; then
      exec 3>&-
      echo "Port $CONTAINER_PORT is already in use. Stop whatever is using it and try again."
      exit 1
    fi

    if [ -n "$STATUS" ]; then
      # Container exists but is stopped - just start it again
      echo "Starting existing container..."
      docker start "$CONTAINER_NAME" >/dev/null
    else
      # Container doesn't exist yet - create and start it
      echo "Starting container..."
      docker run -d \
        --name="$CONTAINER_NAME" \
        -p "$CONTAINER_PORT:80" \
        -v "$APP_SOURCE:/usr/share/nginx/html:ro" \
        "$CONTAINER_IMAGE" > /dev/null
    fi

    # Check the status of the container again, to see if it's healthy and running
    STATUS=$(get_status)
    [ "$STATUS" != "running" ] && echo "Hmm, container doesn't seem to run... Please check: docker logs $CONTAINER_NAME" && exit 1

    echo "Container is running on port: $CONTAINER_PORT"
    echo "http://127.0.0.1:$CONTAINER_PORT or http://$HOSTNAME:$CONTAINER_PORT"
    ;;

  stop)
    STATUS=$(get_status)
    [ -z "$STATUS" ] && echo "$CONTAINER_NAME does not exist." && exit 0
    [ "$STATUS" != "running" ] && echo "$CONTAINER_NAME is not running." && exit 0
    # Stopping the container
    echo 'Stopping container...'
    docker stop "$CONTAINER_NAME" >/dev/null
    ;;

  restart)
    # Restart is just stop followed by start
    "$0" stop
    "$0" start
    ;;

  destroy)
    # Check if container exists
    STATUS=$(get_status)
    [ -z "$STATUS" ] && echo "$CONTAINER_NAME does not exist." && exit 0

    # Destroying the container..
    echo 'Destroying container...'
    [ "$STATUS" = "running" ] && docker stop "$CONTAINER_NAME" >/dev/null
    docker rm "$CONTAINER_NAME" >/dev/null
    ;;

  status)
    STATUS=$(get_status)
    if [ -z "$STATUS" ]; then
      echo "$CONTAINER_NAME does not exist."
    else
      echo "$CONTAINER_NAME is $STATUS."
    fi
    ;;

  logs)
    STATUS=$(get_status)
    [ -z "$STATUS" ] && echo "$CONTAINER_NAME does not exist." && exit 0
    docker logs -f "$CONTAINER_NAME"
    ;;

  *)
    echo "Unknown command: $1"
    echo 'Usage: start, stop, restart, destroy, status, logs'
    exit 1
    ;;
esac
