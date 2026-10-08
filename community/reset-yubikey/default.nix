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
  cfg = config.securix.reset-yubikey;
in
{
  options.securix.reset-yubikey = {
    enable = lib.mkEnableOption "Reset yubikey service";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.yubikey-manager
      (pkgs.writeShellScriptBin "reset-yubikey" ''
        set -e # Exit on error

        # --- Colors for UI ---
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        NC='\033[0m' # No Color

        LOG_FILE="yubikey_erasure_report.txt"

        echo -e "''${BLUE}===============================================''${NC}"
        echo -e "''${BLUE}   YUBIKEY FACTORY RESET & AUDIT TOOL          ''${NC}"
        echo -e "''${BLUE}===============================================''${NC}"

        # 1. Check if ykman is installed
        if ! command -v ykman &> /dev/null; then
            echo -e "''${RED}Error: yubikey-manager (ykman) is not installed.''${NC}"
            exit 1
        fi

        # 2. Identify Device
        echo -e "\n''${YELLOW}[STEP] Identifying Device...''${NC}"
        if ! ykman info; then
            echo -e "''${RED}Error: No YubiKey detected. Please plug in your device.''${NC}"
            exit 1
        fi

        # 3. Security Confirmation
        echo -e "\n''${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!''${NC}"
        echo -e "''${RED}WARNING: THIS WILL PERMANENTLY ERASE ALL SECRETS!''${NC}"
        echo -e "''${RED}This includes FIDO2, SSH keys, GPG keys, and 2FA codes.''${NC}"
        echo -e "''${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!''${NC}"
        echo
        read -p "Are you sure you want to proceed with the reset? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            echo -e "\nOperation aborted by user."
            exit 0
        fi

        # 4. Reset Sequence
        echo -e "\n''${YELLOW}[STEP 1/5] Resetting FIDO2...''${NC}"
        echo -e "''${BLUE}ACTION REQUIRED:''${NC} Unplug your YubiKey, plug it back in, and press ENTER immediately."
        read -s # Wait for enter
        echo "Touch the YubiKey when it flashes..."
        ykman fido reset -f

        echo -e "\n''${YELLOW}[STEP 2/5] Resetting OTP Slots...''${NC}"
        ykman otp delete 1 -f || echo -e "''${YELLOW}Slot 1 already empty or restricted.''${NC}"
        sleep 1
        ykman otp delete 2 -f || echo -e "''${YELLOW}Slot 2 already empty or restricted.''${NC}"

        echo -e "\n''${YELLOW}[STEP 3/5] Resetting PIV (Smart Card)...''${NC}"
        ykman piv reset -f

        echo -e "\n''${YELLOW}[STEP 4/5] Resetting OpenPGP...''${NC}"
        ykman openpgp reset -f

        echo -e "\n''${YELLOW}[STEP 5/5] Resetting OATH (TOTP/HOTP)...''${NC}"
        ykman oath reset -f

        # 5. Evidence Generation
        echo -e "\n''${BLUE}===============================================''${NC}"
        echo -e "''${BLUE}        GENERATING ERASURE EVIDENCE            ''${NC}"
        echo -e "''${BLUE}===============================================''${NC}"

        {
            echo "==============================================================="
            echo "            YUBIKEY ERASURE AUDIT REPORT"
            echo "            Date: $(date -u) (UTC)"
            echo "==============================================================="
            echo -e "\n[1] HARDWARE IDENTIFICATION"
            ykman info
            echo -e "\n[2] FIDO2 STATUS (Should show 'Not set')"
            ykman fido info
            echo -e "\n[3] OTP STATUS (Slots should be 'empty')"
            ykman otp info
            echo -e "\n[4] PIV STATUS (Should show default PIN/PUK warnings)"
            ykman piv info
            echo -e "\n[5] OATH STATUS (Should be empty)"
            ykman oath accounts list
            echo -e "\n[6] OPENPGP STATUS (Keys should be 'None')"
            ykman openpgp info
            echo "==============================================================="
            echo "END OF REPORT"
        } > "$LOG_FILE"

        # 6. Final Output
        cat "$LOG_FILE"

        echo -e "\n''${GREEN}[SUCCESS] YubiKey has been factory reset.''${NC}"
        echo -e "''${GREEN}[SUCCESS] Audit report saved to: ''${NC}$LOG_FILE"
      '')
    ];
    security.sudo.extraRules = [
      {
        groups = [ "operator" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/reset-yubikey";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
