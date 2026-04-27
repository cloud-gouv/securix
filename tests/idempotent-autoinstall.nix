# SPDX-FileCopyrightText: 2026 Mattias Kockum <mattias@kockum.net>
#
# SPDX-License-Identifier: MIT
#
# Regression test for https://github.com/cloud-gouv/securix/issues/171
#
# Boots a Securix installer then runs `autoinstall-terminal` twice.
# The second run must succeed, which only happens if dm-crypt
# handles are properly closed before wiping the disk.

{ pkgs, libSecurix }:

let
  lib = pkgs.lib;

  targetSystem = pkgs.nixos (
    { lib, ... }:
    {
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
                type = "luks";
                name = "securix-root";
                passwordFile = "/tmp/disk-passphrase";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };

        users.users.root.initialPassword = "test";
        fileSystems."/".device = "/dev/mapper/securix-root";
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
      tpm2HostKeys = false;
      ageHostKeys = false;
    };
  };

  autoinstallPkg = lib.findFirst (
    p: p.name or "" == "autoinstall-terminal"
  ) (throw "autoinstall-terminal not found in installer packages") installer.config.environment.systemPackages;

in
pkgs.testers.nixosTest {
  name = "autoinstall-terminal-idempotent";

  nodes.machine =
    { ... }:
    {
      virtualisation.emptyDiskImages = [ 4096 ];
      environment.systemPackages = [
        autoinstallPkg
        pkgs.expect
      ];
    };

  testScript = ''
    import textwrap

    run_autoinstall = textwrap.dedent("""\
        expect <<'EXPECT_EOF'
        set timeout 300
        spawn autoinstall-terminal
        expect "Proceed with reformatting?"
        send "\r"
        expect {
            "Installation is complete" { exit 0 }
            timeout { puts "TIMEOUT"; exit 1 }
            eof { puts "UNEXPECTED EOF"; exit 1 }
        }
        EXPECT_EOF
    """)

    machine.start()
    machine.wait_for_unit("multi-user.target")

    machine.succeed("echo -n 'testpassphrase' > /tmp/disk-passphrase")

    machine.succeed(run_autoinstall)
    machine.succeed(run_autoinstall)
  '';
}
