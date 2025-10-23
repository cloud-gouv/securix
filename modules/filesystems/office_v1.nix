# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

# NOTE: differences with `securix_v1`
# - FIDO2 & recovery are enrolled in the LUKS partition. That's it.
{ lib, config, ... }:
let
  cfg = config.securix.filesystems;
  inherit (lib) mkIf;
  disk = config.securix.self.mainDisk;
in
{
  config = mkIf (cfg.enable && cfg.layout == "office_v1") {
    disko.devices = {
      disk = {
        ${disk} = {
          device = "${disk}";
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                end = "1G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                };
              };
              Recovery = {
                end = "+2G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/recovery";
                };
              };
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "croot";
                  settings = {
                    allowDiscards = true;
                  };
                  enrollFido2 = true;
                  enrollRecovery = true;
                  content = {
                    type = "btrfs";
                    mountpoint = "/";
                    subvolumes = {
                      "/home" = {
                        mountpoint = "/home";
                        mountOptions = [
                          "compress=zstd"
                          "noatime"
                        ];
                      };
                      "/var" = {
                        mountpoint = "/var";
                        mountOptions = [
                          "compress=zstd"
                          "noatime"
                        ];
                      };
                      "/nix" = {
                        mountpoint = "/nix";
                        mountOptions = [
                          "compress=zstd"
                          "noatime"
                        ];
                      };
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
