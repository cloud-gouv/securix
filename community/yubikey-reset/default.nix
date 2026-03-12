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
  cfg = config.securix.yubikey-reset;
in
{
  options.securix.yubikey-reset = {
    enable = lib.mkEnableOption "yubikey-reset CLI tool (factory reset & audit)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "yubikey-reset" ''
        set -euo pipefail

        # --- Colors ---
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        NC='\033[0m'

        LOG_FILE="yubikey_erasure_report_$(date -u +%Y%m%dT%H%M%SZ).txt"

        echo -e "''${BLUE}===============================================''${NC}"
        echo -e "''${BLUE}   YUBIKEY FACTORY RESET & AUDIT TOOL          ''${NC}"
        echo -e "''${BLUE}===============================================''${NC}"

        # 1. Identify Device
        echo -e "\n''${YELLOW}[STEP] Identifying Device...''${NC}"
        if ! ${pkgs.yubikey-manager}/bin/ykman info; then
          echo -e "''${RED}Error: No YubiKey detected. Please plug in your device.''${NC}"
          exit 1
        fi

        # 2. Security Confirmation
        echo -e "\n''${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!''${NC}"
        echo -e "''${RED}WARNING: THIS WILL PERMANENTLY ERASE ALL SECRETS!''${NC}"
        echo -e "''${RED}This includes FIDO2, SSH keys, GPG keys, and 2FA codes.''${NC}"
        echo -e "''${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!''${NC}"
        echo
        read -rp "Are you sure you want to proceed with the reset? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
          echo -e "\nOperation aborted by user."
          exit 0
        fi

        # 3. Reset Sequence
        echo -e "\n''${YELLOW}[STEP 1/5] Resetting FIDO2...''${NC}"
        echo -e "''${BLUE}ACTION REQUIRED:''${NC} Unplug your YubiKey, plug it back in, and press ENTER immediately."
        read -rs _
        echo "Touch the YubiKey when it flashes..."
        ${pkgs.yubikey-manager}/bin/ykman fido reset -f

        echo -e "\n''${YELLOW}[STEP 2/5] Resetting OTP Slots...''${NC}"
        ${pkgs.yubikey-manager}/bin/ykman otp delete 1 -f \
          || echo -e "''${YELLOW}Slot 1 already empty or restricted.''${NC}"
        sleep 1
        ${pkgs.yubikey-manager}/bin/ykman otp delete 2 -f \
          || echo -e "''${YELLOW}Slot 2 already empty or restricted.''${NC}"

        echo -e "\n''${YELLOW}[STEP 3/5] Resetting PIV (Smart Card)...''${NC}"
        ${pkgs.yubikey-manager}/bin/ykman piv reset -f

        echo -e "\n''${YELLOW}[STEP 4/5] Resetting OpenPGP...''${NC}"
        ${pkgs.yubikey-manager}/bin/ykman openpgp reset -f

        echo -e "\n''${YELLOW}[STEP 5/5] Resetting OATH (TOTP/HOTP)...''${NC}"
        ${pkgs.yubikey-manager}/bin/ykman oath reset -f

        # 4. Evidence Generation
        echo -e "\n''${BLUE}===============================================''${NC}"
        echo -e "''${BLUE}        GENERATING ERASURE EVIDENCE            ''${NC}"
        echo -e "''${BLUE}===============================================''${NC}"

        {
          echo "==============================================================="
          echo "            YUBIKEY ERASURE AUDIT REPORT"
          echo "            Date: $(date -u) (UTC)"
          echo "==============================================================="
          echo ""
          echo "[1] HARDWARE IDENTIFICATION"
          ${pkgs.yubikey-manager}/bin/ykman info
          echo ""
          echo "[2] FIDO2 STATUS (Should show 'Not set')"
          ${pkgs.yubikey-manager}/bin/ykman fido info
          echo ""
          echo "[3] OTP STATUS (Slots should be 'empty')"
          ${pkgs.yubikey-manager}/bin/ykman otp info
          echo ""
          echo "[4] PIV STATUS (Should show default PIN/PUK warnings)"
          ${pkgs.yubikey-manager}/bin/ykman piv info
          echo ""
          echo "[5] OATH STATUS (Should be empty)"
          ${pkgs.yubikey-manager}/bin/ykman oath accounts list
          echo ""
          echo "[6] OPENPGP STATUS (Keys should be 'None')"
          ${pkgs.yubikey-manager}/bin/ykman openpgp info
          echo "==============================================================="
          echo "END OF REPORT"
        } > "$LOG_FILE"

        cat "$LOG_FILE"

        echo -e "\n''${GREEN}[SUCCESS] YubiKey has been factory reset.''${NC}"
        echo -e "''${GREEN}[SUCCESS] Audit report saved to: $(pwd)/$LOG_FILE''${NC}"
      '')
    ];
    security.sudo.extraRules = [
      {
        groups = [ "operator" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/yubikey-reset";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
