# SPDX-FileCopyrightText: 2026 Quentin Cazier <cazierquentin@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# Regression test for https://github.com/cloud-gouv/securix/issues/131
#
# Boots a Securix installer whose configured disk does not exist, picks the
# disk offered by `autoinstall-terminal` and checks that the installation
# lands on it. A second run must not ask again.

{ pkgs, libSecurix }:

let
  lib = pkgs.lib;

  targetSystem = pkgs.nixos (
    { lib, ... }: {
      imports = [ "${pkgs.disko.src}/module.nix" ];

      options.securix.self.mainDisk = lib.mkOption { type = lib.types.str; };

      config = {
        securix.self.mainDisk = "/dev/nvme0n1";

        disko.devices.disk.main = {
          device = "/dev/nvme0n1";
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
      skipPreflightCheck = true;
      tpm2HostKeys = false;
      ageHostKeys = false;
    };
  };

  autoinstallPkg =
    lib.findFirst (p: p.name or "" == "autoinstall-terminal")
      (throw "autoinstall-terminal not found in installer packages")
      installer.config.environment.systemPackages;

in
pkgs.testers.nixosTest {
  name = "autoinstall-terminal-missing-disk";

  nodes.machine = _: {
    virtualisation.emptyDiskImages = [ 4096 ];
    environment.systemPackages = [
      autoinstallPkg
      pkgs.expect
    ];
  };

  testScript = ''
    import textwrap

    first_run = textwrap.dedent("""\
        expect <<'EXPECT_EOF'
        set timeout 300
        spawn autoinstall-terminal
        expect "Installation disk"
        sleep 1
        send "\r"
        expect "Proceed with reformatting?"
        send "\r"
        expect {
            "Installation is complete" { exit 0 }
            timeout { puts "TIMEOUT"; exit 1 }
            eof { puts "UNEXPECTED EOF"; exit 1 }
        }
        EXPECT_EOF
    """)

    second_run = textwrap.dedent("""\
        expect <<'EXPECT_EOF'
        set timeout 300
        spawn autoinstall-terminal
        expect {
            "Installation disk" { puts "ASKED AGAIN"; exit 1 }
            "Proceed with reformatting?" { send "\r" }
            timeout { puts "TIMEOUT"; exit 1 }
            eof { puts "UNEXPECTED EOF"; exit 1 }
        }
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
    machine.fail("test -e /dev/nvme0n1")

    machine.succeed(first_run)
    machine.succeed("test \"$(readlink /dev/nvme0n1)\" = /dev/vdb")
    machine.succeed("lsblk -no PARTLABEL /dev/vdb | grep -q disk-main-root")

    machine.succeed(second_run)
  '';
}
