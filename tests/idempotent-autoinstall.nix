# SPDX-FileCopyrightText: 2026 Mattias Kockum <mattias@kockum.net>
# SPDX-FileContributor: 2026 Sébastien Celles <s.celles@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# Regression test for https://github.com/cloud-gouv/securix/issues/171
# and https://github.com/cloud-gouv/securix/issues/287
#
# Boots a Securix installer then runs `autoinstall-terminal` twice.
# The second run must succeed, which only happens if dm-crypt
# handles are properly closed before wiping the disk.
# Then runs it with self-contained Secure Boot: the UEFI firmware loads
# option ROMs (QEMU's network card), so sbctl refuses to enroll the keys
# and the installer must report it.

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
      skipPreflightChecks = true;
      tpm2HostKeys = false;
      ageHostKeys = false;
    };
  };

  findAutoinstall =
    installer:
    lib.findFirst (p: p.name or "" == "autoinstall-terminal")
      (throw "autoinstall-terminal not found in installer packages")
      installer.config.environment.systemPackages;

  autoinstallPkg = findAutoinstall installer;

  secureBootTargetSystem = pkgs.nixos (
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
            partitions = {
              ESP = {
                size = "256M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                };
              };
              root = {
                size = "100%";
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
        boot.loader.grub.enable = false;
        environment.systemPackages = [ pkgs.sbctl ];
        system.stateVersion = lib.trivial.release;
      };
    }
  );

  secureBootAutoinstallPkg = findAutoinstall (
    libSecurix.buildInstallerSystem {
      targetSystem = secureBootTargetSystem;
      preprovisionOptions = {
        secureBoot = "self-contained";
        skipPreflightChecks = true;
        tpm2HostKeys = false;
        ageHostKeys = false;
      };
    }
  );

in
pkgs.testers.nixosTest {
  name = "autoinstall-terminal-idempotent";

  nodes.machine = _: {
    virtualisation = {
      useBootLoader = true;
      useEFIBoot = true;
      efi.OVMF = pkgs.OVMFFull.fd;
      tpm.enable = true;
      emptyDiskImages = [ 4096 ];
      memorySize = 2048;
    };
    boot.loader.systemd-boot.enable = true;
    environment.systemPackages = [
      autoinstallPkg
      pkgs.expect
    ];
    system.extraDependencies = [
      secureBootTargetSystem.config.system.build.toplevel
      secureBootAutoinstallPkg
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

    with subtest("A refused Secure Boot enrollment is reported"):
        setup_mode = "od -An -t u1 /sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"
        assert machine.succeed(setup_mode).split()[-1] == "1"
        _, out = machine.execute(
            "expect <<'EXPECT_EOF' 2>&1\n"
            "set timeout 900\n"
            "spawn ${secureBootAutoinstallPkg}/bin/autoinstall-terminal\n"
            'expect "Proceed with reformatting?"\nsend "\\r"\n'
            "expect eof\n"
            "EXPECT_EOF",
            timeout=1200,
        )
        assert "OptionROM" in out, out
        assert "Secure Boot keys were not enrolled" in out, out
        assert machine.succeed(setup_mode).split()[-1] == "1"
  '';
}
