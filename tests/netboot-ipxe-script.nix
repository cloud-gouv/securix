# SPDX-FileCopyrightText: 2026 T2an
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
let
  lib = pkgs.lib;

  baseModules = [
    {
      options.securix.self.mainDisk = lib.mkOption { type = lib.types.str; };
      config.securix.self.mainDisk = "/dev/vdb";
    }
    ({ lib, ... }: {
      imports = [ "${pkgs.disko.src}/module.nix" ];
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
      fileSystems."/".device = lib.mkForce "/dev/vdb1";
      fileSystems."/".fsType = "ext4";
      boot.loader.grub.enable = false;
    })
  ];

  installer = libSecurix.buildNetbootInstaller {
    inherit baseModules;
    installScript = "echo skip";
    extraInstallerModules = [
      {
        fileSystems."/" = {
          fsType = "tmpfs";
          device = "tmpfs";
          options = [ "mode=0755" ];
        };
      }
    ];
  };

  ipxeScript = installer.config.system.build.netbootIpxeScript.text;
  toplevel = installer.config.system.build.toplevel;
  kernel = installer.config.system.build.kernel;
in
pkgs.runCommand "netboot-ipxe-script"
  {
    passAsFile = [ "ipxeScript" ];
    inherit ipxeScript;
  }
  ''
    head -n1 "$ipxeScriptPath" | grep -qx '#!ipxe' || {
      echo "missing #!ipxe shebang" >&2
      exit 1
    }

    kernelLine=$(grep '^kernel ' "$ipxeScriptPath") || {
      echo "missing kernel line" >&2
      exit 1
    }
    kernelFile=$(echo "$kernelLine" | cut -d' ' -f2)
    [ -e "${kernel}/$kernelFile" ] || {
      echo "kernel file '$kernelFile' from the ipxe script doesn't exist in ${kernel}" >&2
      ls "${kernel}" >&2
      exit 1
    }
    echo "$kernelLine" | grep -q "init=${toplevel}/init " || {
      echo "kernel line doesn't reference this installer's own toplevel" >&2
      echo "$kernelLine" >&2
      exit 1
    }

    grep -qx 'initrd initrd' "$ipxeScriptPath" || { echo "missing initrd line" >&2; exit 1; }
    grep -qx 'boot' "$ipxeScriptPath" || { echo "missing boot line" >&2; exit 1; }

    touch $out
  ''
