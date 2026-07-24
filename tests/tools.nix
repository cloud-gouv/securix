# SPDX-FileCopyrightText: 2026 Pamplemousse <xavier.maso@beta.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
let
  terminalWith =
    {
      name,
      serialNumber,
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
                inherit serialNumber;
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
    extraSecurixConfig = {
      tools.enable = true;
    };
  });
  terminal-without-tools = libSecurix.mkTerminal (terminalWith {
    name = "tools";
    serialNumber = "000001";
    extraSecurixConfig = { };
  });
in
pkgs.testers.nixosTest {
  name = "tools";
  nodes = {
    securix-unbranded-000000 = {
      imports = terminal-with-tools.modules;
    };
    securix-unbranded-000001 = {
      imports = terminal-without-tools.modules;
    };
  };
  testScript = ''
    securix_with_tools = securix_unbranded_000000
    securix_without_tools = securix_unbranded_000001

    securix_with_tools.wait_for_unit("default.target")
    securix_without_tools.wait_for_unit("default.target")

    securix_with_tools.succeed("vim --version")
    securix_without_tools.fail("vim --version")
  '';
}
