{ config, lib, pkgs, ... }:

let
  cfg = config.securix.grist-registration;
in
{
  options.securix.grist-registration = {
    enable = lib.mkEnableOption "Grist registration service";
    gristUrl = lib.mkOption { type = lib.types.str; default = "https://grist.numerique.gouv.fr"; };
    docId = lib.mkOption { type = lib.types.str; };
    tableId = lib.mkOption { type = lib.types.str; };
    useProxy = lib.mkOption { type = lib.types.bool; };
    proxyUrl = lib.mkOption { type = lib.types.nullOr lib.types.str; };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "grist-register" ''
        set -euo pipefail
        
        DETECTED_PROXY="''${http_proxy:-''${https_proxy:-}}"
        
        if [ "${toString cfg.useProxy}" = "0" ]; then
          DETECTED_PROXY=""
        fi
        # Données dynamiques
        INV=$(${pkgs.dmidecode}/bin/dmidecode -s system-serial-number || echo "unknown")
        SKU=$(${pkgs.dmidecode}/bin/dmidecode -s system-version || echo "unknown")
        DATE=$(date -Iseconds)
        SSH=$([ -f /etc/ssh/ssh_host_ed25519_key.pub ] && cat /etc/ssh/ssh_host_ed25519_key.pub || echo "unknown")
        TPM=$([ -f /etc/ssh/ssh_tpm_host_ecdsa_key.pub ] && cat /etc/ssh/ssh_tpm_host_ecdsa_key.pub || echo "unknown")

        PAYLOAD=$(${pkgs.jq}/bin/jq -n \
          --arg i "$INV" --arg h "$SKU" --arg s "$SSH" --arg t "$TPM" --arg d "$DATE" \
          '{records:[{fields:{InventoryID:$i,Hardware:$h,SSHPublicKey:$s,TPMPublicKey:$t,InstallDate:$d}}] }')

        echo "Envoi vers Grist (Proxy utilisé: ''${DETECTED_PROXY:-AUCUN})"

        ${pkgs.curl}/bin/curl -sf \
          ''${DETECTED_PROXY:+ -x "$DETECTED_PROXY"} \
          -X POST \
          -H "Content-Type: application/json" \
          -d "$PAYLOAD" \
          "${cfg.gristUrl}/api/docs/${cfg.docId}/tables/${cfg.tableId}/records" 
      '')
    ];
    security.sudo.extraRules = [{
      groups = [ "operator" ];
      commands = [{ command = "/run/current-system/sw/bin/grist-register"; options = [ "NOPASSWD" ]; }];
    }];
  };
}