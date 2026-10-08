# SPDX-FileCopyrightText: 2026 Quentin Cazier <cazierquentin@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# Test for https://github.com/cloud-gouv/securix/issues/254
#
# Installs a system with journal sealing enabled, reads the verification key
# printed by the installer, boots the installed disk and verifies the journal
# with that key.

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
        ../modules/journald-fss.nix
        (modulesPath + "/testing/test-instrumentation.nix")
        (modulesPath + "/profiles/qemu-guest.nix")
      ];

      options.securix.self.mainDisk = lib.mkOption { type = lib.types.str; };

      config = {
        securix.self.mainDisk = "/dev/vdb";
        securix.filesystems.layout = "securix_v1";
        securix.journaldFSS.enable = true;

        disko.devices.disk."/dev/vdb".content.partitions.luks.content.passwordFile = "${diskKey}";
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
      skipPreflightChecks = true;
      tpm2HostKeys = false;
      ageHostKeys = false;
    };
  };

  autoinstallPkg =
    lib.findFirst (p: p.name or "" == "autoinstall-terminal")
      (throw "autoinstall-terminal not found in installer packages")
      installer.config.environment.systemPackages;

  installRun = pkgs.writeText "install-run.exp" ''
    set timeout 600
    spawn autoinstall-terminal
    expect "Proceed with reformatting?"
    send "\r"
    expect "Verification key written down?"
    send "\r"
    expect {
      "Installation is complete" {}
      timeout { puts "TIMEOUT"; exit 1 }
      eof { puts "UNEXPECTED EOF"; exit 1 }
    }
    expect eof
    lassign [wait] pid spawnid os_error value
    exit $value
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
  name = "journald-fss";

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
    import re

    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("the installer generates the keys and prints the verification key"):
        machine.succeed("expect ${installRun} > /tmp/install.out 2>&1")
        out = machine.succeed("tr -d '\\r' < /tmp/install.out")
        found = re.search(r"[0-9a-f]{6}(?:-[0-9a-f]{6}){3}/[0-9a-f]+-[0-9a-f]+", out)
        assert found, "no verification key in the installer output"
        key = found.group(0)
        machine.succeed("grep -q -E '█|▀|▄' /tmp/install.out")
        machine.succeed("test -s /mnt/var/log/journal/$(cat /mnt/etc/machine-id)/fss")

    machine.succeed("sync")
    machine.shutdown()

    disk = f"{machine.state_dir}/empty0.qcow2"
    booted = create_machine(
        start_command=f"${bootInstalledDisk} -drive file={disk},id=installed,if=none,werror=report",
        name="booted",
    )
    driver.machines_qemu.append(booted)
    booted.start()
    booted.wait_for_unit("multi-user.target")

    with subtest("the installed system seals its journal"):
        booted.succeed("journalctl --header | grep -q 'Compatible flags:.*SEALED'")
        booted.succeed("logger -t fss-test 'hello sealed journal'")
        booted.sleep(5)
        booted.succeed(f"journalctl --verify --verify-key={key}")
        booted.succeed("journalctl -t fss-test | grep -q 'hello sealed journal'")

    with subtest("a wrong key is rejected"):
        wrong = "000000-000000-000000-000000/" + key.split("/")[1]
        booted.fail(f"journalctl --verify --verify-key={wrong}")
  '';
}
