# SPDX-FileCopyrightText: 2026 Contributors
# SPDX-License-Identifier: MIT
#
# Samsung Galaxy Book6 Enterprise Edition — Model PVAP
# CPU: Intel Core Ultra 5 325 (Panther Lake)

{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  inherit (lib) mkIf;
in
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  config = mkIf (config.securix.self.machine.hardwareSKU == "galaxybook6-pvap") {

    boot.initrd.availableKernelModules = [
      "xhci_pci"
      "thunderbolt"
      "nvme"
      "usb_storage"
      "sd_mod"
      "i2c_designware_platform"
      "i2c_hid_acpi"
    ];

    boot.initrd.kernelModules = [ ];

    boot.kernelModules = [
      "kvm-intel"
      "samsung-galaxybook"
    ];

    boot.extraModulePackages = [ ];

    boot.kernelParams = [
      "i8042.nopnp"
      "i8042.reset"
      "i8042.probe_defer"
    ];

    hardware.firmware = [
      pkgs.linux-firmware
      pkgs.wireless-regdb
    ];

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
