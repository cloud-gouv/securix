# SPDX-FileCopyrightText: 2026 Mattias Kockum <mattias@kockum.net>
#
# SPDX-License-Identifier: MIT
#
# Integration test for the refactored inventory system.
# Verifies that a user declared via securix.inventory.users ends up
# correctly provisioned on the resulting NixOS system, without readInventory2.

{ pkgs, libSecurix }:
let

  terminal = libSecurix.mkTerminal-refactor {
    name = "ABC123";
    vpnProfiles = { };
    modules = [
      {
        securix.inventory.machine = {
          hardwareSKU = "x280";
          serialNumber = "ABC123";
          mainDisk = "/dev/nvme0n1";
          users = [ "alice" ];
        };
        securix.graphical-interface.variant = "sway";
      }
      ({ pkgs, ... }: {
        securix.inventory.users.alice = {
          email = "alice@example.com";
          hashedPassword = "$y$j9T$zk4xGLyshz7RzqnMX6M8O0$AybRelILMkQSWcQZV4s.ykRNi/UlgaCUaDwdee0n7N2";
          shell = pkgs.bash;
        };
      })
    ];
  };

in
pkgs.testers.nixosTest {
  name = "inventory-refactor";
  nodes = {
    securix-unbranded-ABC123 = {
      imports = terminal.modules;
    };
  };
  testScript = ''
    securix_unbranded_ABC123.wait_for_unit("default.target")
    securix_unbranded_ABC123.succeed("id alice")
    securix_unbranded_ABC123.succeed("getent passwd alice | grep -q alice")
  '';
}
