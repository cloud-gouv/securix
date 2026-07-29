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
          proxies = {
            dyntest = {
              definition = "dynamic";
              remotePath = pkgs.writeText "secret" ''
                ADDRESS=1.2.3.4
                PORT=8080
              '';
            };
          };
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
    import json

    securix = securix_unbranded_000000
    securix.wait_for_unit("default.target")
    securix.succeed("cat /etc/os-release | grep securix")
    securix.wait_for_unit("portail.service")
    securix.succeed("systemctl restart portail.service")
    securix.wait_for_unit("portail.service")
    assert json.loads(securix.succeed("portail rpc --json list-backends"))[0]['spec'] is not None, "Specification did not get reloaded"
  '';
}
