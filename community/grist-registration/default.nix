# SPDX-FileCopyrightText: 2026 Pauline Legrand <pauline.legrand@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.securix.grist-registration;
in
{
  options.securix.grist-registration = {
    enable = lib.mkEnableOption "Grist registration service";
    gristUrl = lib.mkOption { type = lib.types.str; };
    docId = lib.mkOption { type = lib.types.str; };
    tableId = lib.mkOption { type = lib.types.str; };
    useProxy = lib.mkOption { type = lib.types.bool; };
    proxyUrl = lib.mkOption { type = lib.types.nullOr lib.types.str; };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "grist-register" ''
        set -euo pipefail

        log_journal() {
          ${pkgs.util-linux}/bin/logger -s -t grist-registration -p "user.$1" "$2"
        }

        log_journal "info" "Lancement de l'enregistrement Grist..."

        # Gestion du Proxy
        DETECTED_PROXY="''${http_proxy:-''${https_proxy:-}}"

        if [ "${toString cfg.useProxy}" = "0" ]; then
          DETECTED_PROXY=""
        else
          log_journal "info" "Configuration réseau : Proxy détecté."
        fi

        # Données dynamiques
        INV=$(${pkgs.dmidecode}/bin/dmidecode -s system-serial-number 2>/dev/null || echo "unknown")
        SKU=$(${pkgs.dmidecode}/bin/dmidecode -s system-version 2>/dev/null || echo "unknown")
        DATE=$(date -Iseconds)
        SSH=$([ -f /etc/ssh/ssh_host_ed25519_key.pub ] && cat /etc/ssh/ssh_host_ed25519_key.pub || echo "unknown")
        TPM=$([ -f /etc/ssh/ssh_tpm_host_ecdsa_key.pub ] && cat /etc/ssh/ssh_tpm_host_ecdsa_key.pub || echo "unknown")

        PAYLOAD=$(${pkgs.jq}/bin/jq -n \
          --arg i "$INV" --arg h "$SKU" --arg s "$SSH" --arg t "$TPM" --arg d "$DATE" \
          '{records:[{fields:{InventoryID:$i,Hardware:$h,SSHPublicKey:$s,TPMPublicKey:$t,InstallDate:$d}}] }')

        echo "Envoi vers Grist (Proxy utilisé: ''${DETECTED_PROXY:-AUCUN})"
        URL="${cfg.gristUrl}/api/docs/${cfg.docId}/tables/${cfg.tableId}/records"

        RESPONSE=$(${pkgs.curl}/bin/curl -sf -w "\n%{http_code}" \
          ''${DETECTED_PROXY:+ -x "$DETECTED_PROXY"} \
          -X POST \
          -H "Content-Type: application/json" \
          -d "$PAYLOAD" \
          "$URL" || echo -e "\n000")

        HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
        BODY=$(echo "$RESPONSE" | sed '$d')

        if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
          log_journal "info" "Succès : Enregistrement Grist terminé (HTTP $HTTP_CODE)."
        else
          log_journal "err" "Échec de l'enregistrement Grist. Code HTTP: $HTTP_CODE. Réponse: $BODY"
          exit 1
        fi
      '')
    ];
    security.sudo.extraRules = [
      {
        groups = [ "operator" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/grist-register";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
