# SPDX-FileCopyrightText: 2026 Sébastien Celles <s.celles@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# Regression test for https://github.com/cloud-gouv/securix/issues/288
#
# Runs `autoinstall-terminal` with `tpm2HostKeys = true` on a machine with a
# TPM and checks that the TPM-backed host SSH keys are written to the target.
# The target system does not include ssh-tpm-agent, as most do not.

{ pkgs, libSecurix }:

let
  lib = pkgs.lib;

  targetSystem = pkgs.nixos (
    { lib, ... }: {
      imports = [ "${pkgs.disko.src}/module.nix" ];

      options.securix.self.mainDisk = lib.mkOption { type = lib.types.str; };

      config = {
        securix.self.mainDisk = "/dev/vdb";

        disko.devices.disk.main = {
          device = "/dev/vdb";
          type = "disk";
          content = {
            type = "gpt";
            partitions.root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };

        users.users.root.initialPassword = "test";
        fileSystems."/".device = "/dev/vdb1";
        fileSystems."/".fsType = "ext4";
        boot.loader.grub.enable = false;
      };
    }
  );

  installer = libSecurix.buildInstallerSystem {
    inherit targetSystem;
    installScript = "echo 'install skipped for test'";
    preprovisionOptions = {
      secureBoot = "disabled";
      skipPreflightChecks = true;
      tpm2HostKeys = true;
      ageHostKeys = false;
    };
  };

  autoinstallPkg =
    lib.findFirst (p: p.name or "" == "autoinstall-terminal")
      (throw "autoinstall-terminal not found in installer packages")
      installer.config.environment.systemPackages;

in
pkgs.testers.nixosTest {
  name = "autoinstall-terminal-tpm-host-keys";

  nodes.machine = _: {
    virtualisation.emptyDiskImages = [ 1024 ];
    virtualisation.tpm.enable = true;
    environment.systemPackages = [
      autoinstallPkg
      pkgs.expect
    ];
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test -e /dev/tpm0")

    machine.succeed("""expect <<'EXPECT_EOF' >&2
    set timeout 300
    spawn autoinstall-terminal
    expect "Proceed with reformatting?"
    send "\r"
    expect {
        "Installation is complete" { exit 0 }
        timeout { puts "TIMEOUT"; exit 1 }
        eof { puts "UNEXPECTED EOF"; exit 1 }
    }
    EXPECT_EOF""")

    for key in ["ecdsa", "rsa"]:
        machine.succeed(f"test -s /mnt/etc/ssh/ssh_tpm_host_{key}_key.tpm")
        machine.succeed(f"test -s /mnt/etc/ssh/ssh_tpm_host_{key}_key.pub")
  '';
}
