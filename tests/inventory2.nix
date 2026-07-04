# SPDX-FileCopyrightText: 2026 Mattias Kockum <mattias@kockum.net>
#
# SPDX-License-Identifier: MIT
#
# Integration test for readInventory2 + mkTerminal.
# Verifies that a user declared in an inventory2 directory ends up
# correctly provisioned on the resulting NixOS system.

{ pkgs, libSecurix }:
let
  fakeInventory = pkgs.runCommand "fake-inventory" { } ''
    mkdir -p $out/machines $out/users

    cat > $out/machines/ABC123.nix <<'EOF'
    {
      securix.self = {
        mainDisk = "/dev/nvme0n1";
        machine = {
          hardwareSKU = "x280";
          serialNumber = "ABC123";
          users = [ "alice" ];
        };
      };
    }
    EOF

    cat > $out/users/alice.nix <<'EOF'
    { pkgs, ... }:
    {
      securix.self.user = {
        email = "alice@example.com";
        username = "alice";
        hashedPassword = "$y$j9T$zk4xGLyshz7RzqnMX6M8O0$AybRelILMkQSWcQZV4s.ykRNi/UlgaCUaDwdee0n7N2";
        defaultLoginShell = pkgs.bash;
      };
    }
    EOF
  '';

  inventory = libSecurix.readInventory2 { dir = fakeInventory; };

  terminal = libSecurix.mkTerminal {
    name = "ABC123";
    userSpecificModule = { };
    vpnProfiles = { };
    modules = [
      inventory."ABC123".machineModule
      {
        securix.graphical-interface.variant = "sway";
      }
    ] ++ inventory."ABC123".userModules;
  };
in
pkgs.testers.nixosTest {
  name = "inventory2";
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
