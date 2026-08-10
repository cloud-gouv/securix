# SPDX-FileCopyrightText: 2025 Antoine Eiche <aei.ext@hackcyom.com>
# SPDX-FileContributor: 2025 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
let
  terminal = libSecurix.mkTerminal {
    name = "anssi-minimal";
    userSpecificModule = { };
    vpnProfiles = { };
    modules = [
      {
        security.anssi = {
          enable = true;
          level = "minimal";
          category = "client";
        };

        securix = {
          graphical-interface.variant = "sway";
          self = {
            mainDisk = "/dev/nvme0n1";
            machine = {
              hardwareSKU = "x280";
              inventoryId = 0;
            };
          };
        };
      }
    ];
  };
in
pkgs.testers.nixosTest {
  name = "anssi-minimal";
  nodes = {
    securix-unbranded-0 = {
      imports = terminal.modules;
    };
  };
  testScript = ''
    securix_unbranded_0.wait_for_unit("default.target")
    securix_unbranded_0.succeed("cat /etc/os-release | grep securix")
  '';
}
