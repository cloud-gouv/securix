#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

CONFIG_FILE="/etc/proxy-switcher/proxies.json"
DAEMON_GROUP="default"
INTERNAL_FORWARD_PROXY="127.0.0.1:8081"
PID=$(systemctl show -p MainPID --value http-proxy.service)
STATE_FILE="/var/lib/proxy-switcher/current"

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root (use sudo)." >&2
  exit 1
fi

# Ensure the state file exists
if [ ! -f "$STATE_FILE" ]; then
  echo "Creating state file at '$STATE_FILE'..."
  mkdir -p "$(dirname "$STATE_FILE")"
  touch "$STATE_FILE"
fi


publish_proxy() {
  local selected_proxy_ipv4="$1"
  g3proxy-ctl -G "$DAEMON_GROUP" -p "$PID" escaper dynamic publish "{\"addr\": \"$selected_proxy_ipv4\", \"type\": \"http\"}"
}

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file '$CONFIG_FILE' not found!"
  exit 1
fi

# CLI mode.
if [ "$#" -ge 2 ]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "This script requires 'jq'. Please make it available in the environment."
    exit 1
  fi

  case "$1" in
    --list)
      echo "Available proxies:"
      jq -r 'keys[]' "$CONFIG_FILE" | sed 's/^/  - /'
      echo "  - np (No Proxy, use internal forward proxy)"
      exit 0
      ;;
    np)
      echo "Switching to internal forward proxy..."
      publish_proxy "$INTERNAL_FORWARD_PROXY"
      echo "Done."
      exit 0
      ;;
    *)
      SELECTED_ADDR=$(jq -r --arg k "$1" '.[$k] // empty' "$CONFIG_FILE")
      if [ -z "$SELECTED_ADDR" ]; then
        echo "Error: Proxy '$1' not found in $CONFIG_FILE"
        exit 1
      fi
      echo "Switching to: $SELECTED_ADDR"
      publish_proxy "$SELECTED_ADDR"
      echo "Done."
      exit 0
      ;;
  esac

  echo "$1" > "$STATE_FILE"

fi

# TUI fallback if no argument specified.
if ! command -v jq >/dev/null 2>&1 || ! command -v whiptail >/dev/null 2>&1; then
  echo "This script requires 'jq' and 'whiptail'. Please make them available in the environment."
  exit 1
fi

KEYS=($(jq -r 'keys[]' "$CONFIG_FILE"))
MENU_ITEMS=()

for key in "${KEYS[@]}"; do
  ADDR=$(jq -r --arg k "$key" '.[$k]' "$CONFIG_FILE")
  MENU_ITEMS+=("$key" "$ADDR")
done

MENU_ITEMS+=("np" "No Proxy (Use internal forward proxy)")

CHOICE=$(whiptail --title "Proxy Switcher" \
  --menu "Choose a proxy to activate:" 20 70 10 \
  "${MENU_ITEMS[@]}" \
  3>&1 1>&2 2>&3)

EXIT_STATUS=$?
if [ $EXIT_STATUS -ne 0 ]; then
  echo "Cancelled."
  exit 1
fi

if [ "$CHOICE" = "np" ]; then
  echo "Switching to internal forward proxy..."
  publish_proxy "$INTERNAL_FORWARD_PROXY"
else
  SELECTED_ADDR=$(jq -r --arg k "$CHOICE" '.[$k]' "$CONFIG_FILE")
  echo "Switching to: $SELECTED_ADDR"
  publish_proxy "$SELECTED_ADDR"
fi

echo "$CHOICE" > "$STATE_FILE"

echo "Done."
