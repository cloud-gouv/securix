# SPDX-FileCopyrightText: 2026 Quentin Cazier <cazierquentin@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# Regression test for https://github.com/cloud-gouv/securix/issues/131
#
# Installs a system configured for a disk that does not exist on the disk
# picked at the installer prompt, runs the installer a second time, then
# boots a second VM from that disk alone.

{ pkgs, libSecurix }:

let
  lib = pkgs.lib;

  qemu-common = import "${pkgs.path}/nixos/lib/qemu-common.nix" {
    inherit lib;
    inherit (pkgs) stdenv;
  };

  # Unlocks LUKS at install time and from the initrd at boot.
  diskKey = pkgs.writeText "disk-key" "testpassphrase";

  targetSystem = pkgs.nixos (
    { lib, modulesPath, ... }: {
      imports = [
        "${pkgs.disko.src}/module.nix"
        ../modules/filesystems
        (modulesPath + "/testing/test-instrumentation.nix")
        (modulesPath + "/profiles/qemu-guest.nix")
      ];

      options.securix.self.mainDisk = lib.mkOption { type = lib.types.str; };

      config = {
        securix.self.mainDisk = "/dev/nvme0n1";
        securix.filesystems.layout = "securix_v1";

        disko.devices.disk."/dev/nvme0n1".content.partitions.luks.content.passwordFile = "${diskKey}";
        boot.initrd.secrets."/etc/secrets/disk.key" = diskKey;
        boot.initrd.luks.devices.croot.keyFile = "/etc/secrets/disk.key";

        # Securix uses lanzaboote, systemd-boot is enough to boot the disk in a VM.
        # The installer VM is not booted with UEFI, hence graceful.
        boot.loader.systemd-boot.enable = true;
        boot.loader.systemd-boot.graceful = true;

        documentation.enable = false;
        system.stateVersion = "26.05";
      };
    }
  );

  installer = libSecurix.buildInstallerSystem {
    inherit targetSystem;
    preprovisionOptions = {
      secureBoot = "disabled";
      tpm2HostKeys = false;
      ageHostKeys = false;
    };
  };

  autoinstallPkg =
    lib.findFirst (p: p.name or "" == "autoinstall-terminal")
      (throw "autoinstall-terminal not found in installer packages")
      installer.config.environment.systemPackages;

  # Runs autoinstall-terminal with the given answers and waits for it to finish.
  mkInstallRun =
    name: answers:
    pkgs.writeText "${name}.exp" ''
      set timeout 600
      spawn autoinstall-terminal
      ${answers}
      expect {
        "Installation is complete" {}
        timeout { puts "TIMEOUT"; exit 1 }
        eof { puts "UNEXPECTED EOF"; exit 1 }
      }
      expect eof
      lassign [wait] pid spawnid os_error value
      exit $value
    '';

  firstRun = mkInstallRun "first-run" ''
    expect "Installation disk"
    sleep 1
    send "\r"
    expect "Proceed with reformatting?"
    send "\r"
  '';

  secondRun = mkInstallRun "second-run" ''
    expect {
      "Installation disk" { puts "ASKED AGAIN"; exit 1 }
      "Proceed with reformatting?" { send "\r" }
      timeout { puts "TIMEOUT"; exit 1 }
    }
  '';

  # Boots the installed disk alone, with UEFI firmware.
  bootInstalledDisk = lib.concatStringsSep " " [
    (qemu-common.qemuBinary pkgs.qemu_test)
    "-m 1024"
    "-device virtio-blk-pci,drive=installed"
    "-drive if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}"
    "-drive if=pflash,format=raw,unit=1,readonly=on,file=${pkgs.OVMF.variables}"
  ];
in
pkgs.testers.nixosTest {
  name = "autoinstall-terminal-missing-disk";

  nodes.machine = _: {
    virtualisation.emptyDiskImages = [ 12288 ];
    virtualisation.memorySize = 2048;
    boot.supportedFilesystems = [
      "btrfs"
      "vfat"
    ];
    environment.systemPackages = [
      autoinstallPkg
      pkgs.expect
    ];
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.fail("test -e /dev/nvme0n1")

    with subtest("the installer asks for a disk and installs on it"):
        machine.succeed("expect ${firstRun}")
        machine.succeed("test \"$(readlink /dev/nvme0n1)\" = /dev/vdb")
        machine.succeed("lsblk -no PARTLABEL /dev/vdb | grep -q disk-_dev_nvme0n1-luks")

    with subtest("a second run does not ask again"):
        machine.succeed("expect ${secondRun}")

    machine.succeed("sync")
    machine.shutdown()

    disk = f"{machine.state_dir}/empty0.qcow2"
    booted = create_machine(
        start_command=f"${bootInstalledDisk} -drive file={disk},id=installed,if=none,werror=report",
        name="booted",
    )
    driver.machines_qemu.append(booted)
    booted.start()

    with subtest("the installed system boots from the chosen disk"):
        booted.wait_for_unit("multi-user.target")
        booted.fail("test -e /dev/nvme0n1")
        booted.succeed("findmnt -n -o SOURCE / | grep -q '^/dev/mapper/croot'")
        booted.succeed("cryptsetup status croot | grep -q 'device:.*/dev/vda3'")
  '';
}
