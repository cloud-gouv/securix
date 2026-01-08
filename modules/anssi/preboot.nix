# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  # TODO: these two next rules requires special system integration that depends on the hardware manufacturer.
  # We implement no specific check or implementation here.
  R1 = {
    name = "R1_ChooseHardware";
    anssiRef = "R1 – Choisir et configurer son matériel";
    description = "Choosing and configuring hardware";
    severity = "high";
    category = "base";

    config = _: {
      # TODO: hardware-level config (maybe BIOS settings, firmware)
    };

    checkScript =
      pkgs:
      pkgs.writeShellScript "check-R1" ''
        echo "TODO: check hardware configuration for R1"
        exit 0
      '';
  };

  R2 = {
    name = "R2_BIOS_UEFI";
    anssiRef = "R2 – Configurer le BIOS/UEFI";
    description = "Configure BIOS / UEFI";
    severity = "intermediary";
    category = "base";

    config = _: {
      # TODO: set NixOS options for UEFI / BIOS security
    };

    checkScript =
      pkgs:
      pkgs.writeShellScript "check-R2" ''
        echo "TODO: check BIOS / UEFI secure configuration"
        exit 0
      '';
  };

  R3 = {
    name = "R3_UEFI_SecureBoot";
    anssiRef = "R3 – Activer le démarrage sécurisé UEFI";
    description = "Enable UEFI Secure Boot";
    severity = "intermediary";
    category = "base";

    config = _: {
      # TODO: NixOS bootloader secure-boot config
    };

    checkScript =
      pkgs:
      pkgs.writeShellScript "check-R3" ''
        # Check if the system is running in UEFI mode
        if [ ! -d "/sys/firmware/efi" ]; then
          echo "Secure Boot cannot be checked. System is not in UEFI mode."
          exit 1
        fi

        # Check the Secure Boot status
        secure_boot_file="/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
        if [ -f "$secure_boot_file" ]; then
          # Extract the value of SecureBoot
          secure_boot_status=$(xxd -p -c 4 "$secure_boot_file")

          # Check if Secure Boot is enabled
          if [[ "$secure_boot_status" =~ ".*01.*" ]]; then
            echo "Secure Boot is enabled."
            exit 0
          else
            echo "fail: Secure Boot is not enabled."
            exit 1
          fi
        else
          echo "fail: Secure Boot status file not found."
          exit 1
        fi
      '';
  };

  R4 = {
    name = "R4_ReplacePreloadedKeys";
    anssiRef = "R4 – Remplacer les clés préchargées";
    description = "Replace preloaded UEFI keys";
    severity = "high";
    category = "base";

    config = _: { };

    checkScript =
      pkgs:
      pkgs.writeShellScript "check-R4" ''
        echo "TODO: check all loaded certificates"
        exit 0
      '';
  };

  R5 = {
    name = "R5_BootloaderPassword";
    anssiRef = "R5 – Configurer un mot de passe pour le chargeur de démarrage";
    description = "Set a password on the bootloader";
    severity = "intermediary";
    category = "base";

    implementations = {
      secureboot = {
        checkScript = { };
        depends = [ "R3" ];
        config = _: { };
      };
      grub = {
        checkScript = "";
        config = _: { };
      };
    };

    config = _: {
      # TODO: grub or systemd-boot password
    };

    checkScript =
      pkgs:
      pkgs.writeShellScript "check-R5" ''
        echo "R5 depends on R3."
        exit 0
      '';
  };

  R6 = {
    name = "R6_ProtectKernelCmdline";
    anssiRef = "R6 – Protéger les paramètres de ligne de commande du noyau et l’initramfs";
    description = "Protect kernel cmdline and initramfs";
    severity = "high";
    category = "base";

    # implementations.secureboot = { checkScript = {}; depends = [ "R3" ]; };

    config = _: {
      # TODO
    };

    checkScript =
      pkgs:
      pkgs.writeShellScript "check-R6" ''
        echo "R6 depends on R3."
      '';
  };

  R7 = {
    name = "R7_EnableIOMMU";
    anssiRef = "R7 – Activer l’IOMMU";
    description = "Enable IOMMU";
    severity = "reinforced";
    category = "base";

    config = _: { boot.kernelParams = [ "iommu=force" ]; };

    checkScript =
      pkgs:
      pkgs.writeShellScript "check-R7" ''
        #!/bin/sh

        IOMMU_DIR="/sys/class/iommu"

        if [ -d "$IOMMU_DIR" ] && [ "$(ls -A $IOMMU_DIR)" ]; then
          echo "IOMMU is enabled. Files found: $(ls $IOMMU_DIR | xargs)"
        else
          echo "No IOMMU detected or not enabled."
          exit 1
        fi

        exit 0
      '';
  };
}
