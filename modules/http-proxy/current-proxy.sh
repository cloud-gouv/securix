#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025 Pauline Legrand <pauline.legrand@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

CURRENT_PROXY_FILE="/tmp/current-proxy.json"
PROXIES_LIST_FILE="/etc/proxy-switcher/proxies.json"

if [ -f "$CURRENT_PROXY_FILE" && -f "$PROXIES_LIST_FILE" ]; then
    CURRENT_PROXY_IP=$(jq -r '.[0].addr' "$CURRENT_PROXY_FILE")

    if [ -z "$CURRENT_PROXY_IP" ]; then
        echo "Adresse IP du proxy actuel non déterminée"
        exit 1
    fi

    MATCH=$(jq -r --arg ip "$CURRENT_PROXY_IP" 'to_entries[] | select(.value == $ip ) | .key' "$PROXIES_LIST_FILE")

    if [ -z "$MATCH" ]; then
        echo "Aucun proxy avec l'adresse IP $CURRENT_PROXY_IP dans la liste"
        exit 1
    fi

    NAME=$(echo "$MATCH" | jq -r '.name')

    echo "Vous êtes connecté sur le proxy $NAME ($CURRENT_PROXY_IP)"
fi