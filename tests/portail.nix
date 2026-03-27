# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
let
  terminal = libSecurix.mkTerminal {
    name = "portail";
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

        securix.automatic-http-proxy = {
          enable = true;
          implementation = "portail";
          proxies = { };
        };
      }
    ];
  };
in
pkgs.testers.nixosTest {
  name = "portail";
  nodes = {
    securix-unbranded-000000 = {
      imports = terminal.modules;
    };
  };
  testScript = ''
    securix_unbranded_000000.wait_for_unit("default.target")
    securix_unbranded_000000.succeed("cat /etc/os-release | grep securix")
    securix_unbranded_000000.wait_for_unit("portail.service")
  '';
}
