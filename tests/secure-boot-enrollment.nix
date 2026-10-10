# SPDX-FileCopyrightText: 2026 Sébastien Celles <s.celles@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# Regression test for https://github.com/cloud-gouv/securix/issues/287
#
# Runs `autoinstall-terminal` with self-contained Secure Boot in a UEFI VM
# whose firmware is in setup mode and loads option ROMs (QEMU's network
# card), with a TPM so sbctl can read the event log:
# - with the default flags, sbctl refuses and the failure is reported;
# - with `secureBootEnrollFlags = [ "--microsoft" ]`, the keys are enrolled
#   and the firmware leaves setup mode.

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

  autoinstall =
    flags:
    lib.findFirst (p: p.name or "" == "autoinstall-terminal")
      (throw "autoinstall-terminal not found in installer packages")
      (libSecurix.buildInstallerSystem {
        inherit targetSystem;
        preprovisionOptions = {
          secureBoot = "self-contained";
          secureBootEnrollFlags = flags;
          skipPreflightChecks = true;
          tpm2HostKeys = false;
          ageHostKeys = false;
        };
      }).config.environment.systemPackages;

  defaultFlags = autoinstall [ ];
  microsoft = autoinstall [ "--microsoft" ];
in
pkgs.testers.nixosTest {
  name = "autoinstall-terminal-secure-boot-enrollment";

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
    environment.systemPackages = [ pkgs.expect ];
    system.extraDependencies = [
      targetSystem.config.system.build.toplevel
      defaultFlags
      microsoft
    ];
  };

  testScript = ''
    def install(script):
        return machine.execute(
            "expect <<'EXPECT_EOF' 2>&1\n"
            "set timeout 900\n"
            f"spawn {script}/bin/autoinstall-terminal\n"
            'expect "Proceed with reformatting?"\nsend "\\r"\n'
            "expect eof\n"
            "EXPECT_EOF",
            timeout=1200,
        )[1]

    def setup_mode():
        return machine.succeed(
            "od -An -t u1 /sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"
        ).split()[-1]

    machine.start()
    machine.wait_for_unit("multi-user.target")
    assert setup_mode() == "1", "the firmware must start in setup mode"

    with subtest("Default flags: sbctl refuses and the failure is reported"):
        out = install("${defaultFlags}")
        assert "OptionROM" in out, out
        assert "Secure Boot keys were not enrolled" in out, out
        assert setup_mode() == "1"

    with subtest("--microsoft: the keys are enrolled"):
        out = install("${microsoft}")
        assert "Secure Boot keys were not enrolled" not in out, out
        assert setup_mode() == "0"
  '';
}
