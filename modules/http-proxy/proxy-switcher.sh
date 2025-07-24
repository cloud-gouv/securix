#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

CONFIG_FILE="/etc/proxy-switcher/proxies.json"
DAEMON_GROUP="default"
INTERNAL_FORWARD_PROXY="127.0.0.1:8081"
PID=$(systemctl show -p MainPID --value http-proxy.service)

# Ensure jq and whiptail are available
if ! command -v jq >/dev/null 2>&1 || ! command -v whiptail >/dev/null 2>&1; then
  echo "This script requires 'jq' and 'whiptail'. Please make them available in the environment."
  exit 1
fi

# Ensure config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file '$CONFIG_FILE' not found!"
  exit 1
fi

publish_proxy() {
  local selected_proxy_ipv4="$1"
  g3proxy-ctl -G "$DAEMON_GROUP" -p "$PID" escaper dynamic publish "{\"addr\": \"$selected_proxy_ipv4\", \"type\": \"http\"}"
}

# Build menu from flat JSON
KEYS=($(jq -r 'keys[]' "$CONFIG_FILE"))
MENU_ITEMS=()

for key in "${KEYS[@]}"; do
  ADDR=$(jq -r --arg k "$key" '.[$k]' "$CONFIG_FILE")
  MENU_ITEMS+=("$key" "$ADDR")
done

# Add "No Proxy" option
MENU_ITEMS+=("np" "No Proxy (Use internal forward proxy)")

# Display menu
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

echo "Done."

