# SPDX-FileCopyrightText: 2026 Pamplemousse <xavier.maso@beta.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
let
  terminalWith =
    {
      name,
      serialNumber,
      inventoryId,
      extraSecurixConfig,
    }:
    {
      inherit name;
      userSpecificModule = { };
      vpnProfiles = { };
      modules = [
        {
          securix = {
            graphical-interface.variant = "sway";
            self = {
              mainDisk = "/dev/nvme0n1";
              machine = {
                inherit serialNumber inventoryId;
                hardwareSKU = "x280";
              };
            };
          }
          // extraSecurixConfig;
        }
      ];
    };

  terminal-with-tools = libSecurix.mkTerminal (terminalWith {
    name = "tools";
    serialNumber = "000000";
    inventoryId = 0;
    extraSecurixConfig = {
      tools.enable = true;
    };
  });
  terminal-without-tools = libSecurix.mkTerminal (terminalWith {
    name = "tools";
    serialNumber = "000001";
    inventoryId = 1;
    extraSecurixConfig = { };
  });
in
pkgs.testers.nixosTest {
  name = "tools";
  nodes = {
    securix-unbranded-0 = {
      imports = terminal-with-tools.modules;
    };
    securix-unbranded-1 = {
      imports = terminal-without-tools.modules;
    };
  };
  testScript = ''
    securix_with_tools = securix_unbranded_0
    securix_without_tools = securix_unbranded_1

    securix_with_tools.wait_for_unit("default.target")
    securix_without_tools.wait_for_unit("default.target")

    securix_with_tools.succeed("vim --version")
    securix_without_tools.fail("vim --version")
  '';
}
