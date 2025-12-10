# SPDX-FileCopyrightText: 2025 Antoine Eiche <aei.ext@hackcyom.com>
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
let
  terminal = libSecurix.mkTerminal {
    name = "minimal";
    userSpecificModule = { };
    vpnProfiles = { };
    modules = [
      {
        securix = {
          graphical-interface.variant = "sway";
          self = {
            mainDisk = "/dev/nvme0n1";
            machine = {
              hardwareSKU = "x280";
              serialNumber = "000000";
            };
          };
        };
      }
    ];
  };
in
pkgs.testers.nixosTest {
  name = "minimal";
  nodes = {
    securix-unbranded-000000 = {
      imports = terminal.modules;
    };
  };
  testScript = ''
    securix_unbranded_000000.wait_for_unit("default.target")
    securix_unbranded_000000.succeed("cat /etc/os-release | grep securix")
  '';
}
