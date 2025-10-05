#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025 Pauline Legrand <pauline.legrand@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

CURRENT_PROXY_FILE="$(find /tmp -type d -name "*g3proxy*" 2>/dev/null)/tmp/current-proxy.json"
PROXIES_LIST_FILE="/etc/proxy-switcher/proxies.json"

if [ -f "$CURRENT_PROXY_FILE" ] && [ -f "$PROXIES_LIST_FILE" ]; then
    CURRENT_PROXY_IP=$(jq -r '.[0].addr' "$CURRENT_PROXY_FILE")

    if [ -z "$CURRENT_PROXY_IP" ]; then
        echo "Adresse IP du proxy actuel non déterminée"
        exit 1
    fi

    MATCH=$(jq -r --arg ip "$CURRENT_PROXY_IP" 'to_entries[] | select(.value == $ip ) | .key' "$PROXIES_LIST_FILE")

    if [ -z "$MATCH" ]; then
        if [ "$CURRENT_PROXY_IP" = "127.0.0.1:8081" ]; then
            echo "Vous n'êtes pas connecté à un proxy distant (proxy interne utilisé)"
            exit
        else
            echo "Vous êtes connecté sur le proxy $CURRENT_PROXY_IP dans la liste"
            exit 1
        fi
    fi

    echo "Vous êtes connecté sur le proxy $MATCH ($CURRENT_PROXY_IP)"
fi