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
              inventoryId = 0;
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

        # Test-only: the oneshot exits fast enough that wait_for_unit sees it as
        # "inactive, no pending jobs" more often than not, unless it stays active
        # after a successful run.
        systemd.services.portail-dynamic-updates.serviceConfig.RemainAfterExit = true;
      }
    ];
  };
in
pkgs.testers.nixosTest {
  name = "portail";
  nodes = {
    securix-unbranded-0 = {
      imports = terminal.modules;
    };
  };
  testScript = ''
    import json

    securix = securix_unbranded_0
    securix.wait_for_unit("default.target")
    securix.succeed("cat /etc/os-release | grep securix")
    securix.wait_for_unit("portail.service")
    securix.succeed("systemctl restart portail.service")
    securix.wait_for_unit("portail.service")
    securix.wait_for_unit("portail-dynamic-updates.service")

    # Looked up by id, not by list position: list-backends does not guarantee an order.
    backends = json.loads(securix.succeed("portail rpc --json list-backends"))
    dyntest = next(b for b in backends if b["id"] == "dyntest")
    assert dyntest["spec"] is not None, "Specification did not get reloaded"
  '';
}
