# SPDX-FileCopyrightText: 2026 raltheo <contact@raltheo.fr>
#
# SPDX-License-Identifier: MIT
# ThinkPad X13 (Type 20UF, 20UG) — AMD Ryzen
# Généré depuis nixos-generate-config et adapté pour Securix.

{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  config = lib.mkIf (config.securix.self.machine.hardwareSKU == "x13-20ug") {
    boot.initrd.availableKernelModules = [
      "nvme"
      "ehci_pci"
      "xhci_pci_renesas"
      "xhci_pci"
      "rtsx_pci_sdmmc"
    ];
    boot.initrd.kernelModules = [ ];
    boot.kernelModules = [ "kvm-amd" ];
    boot.extraModulePackages = [ ];

    hardware.firmware = [
      pkgs.linux-firmware
      pkgs.wireless-regdb
    ];

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
