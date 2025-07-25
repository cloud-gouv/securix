# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, ... }:
let
  disk = config.securix.self.mainDisk;
  mountOptions = [ "noatime" ];
in
{
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
}
