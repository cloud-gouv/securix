#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025 Pauline Legrand <pauline.legrand@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

STATE_FILE="/var/lib/proxy-switcher/current"

if [ -f "$STATE_FILE" ]; then
  PROXY_NAME=$(cat "$STATE_FILE")
  echo "Proxy actuellement actif : $PROXY_NAME"
else
  echo "Aucun proxy actif détecté."
fi