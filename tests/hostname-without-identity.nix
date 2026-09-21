# SPDX-FileCopyrightText: 2026 T2an
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
let
  terminal-without-identity = libSecurix.mkTerminal {
    name = "no-identity";
    userSpecificModule = { };
    vpnProfiles = { };
    modules = [
      {
        securix = {
          graphical-interface.variant = "sway";
          self = {
            mainDisk = "/dev/nvme0n1";
            machine.hardwareSKU = "x280";
          };
        };
      }
    ];
  };
in
pkgs.testers.nixosTest {
  name = "hostname-without-identity";
  nodes."securix-unbranded-unknown-machine" = {
    imports = terminal-without-identity.modules;
  };
  testScript = ''
    securix_unbranded_unknown_machine.wait_for_unit("default.target")
    hostname = securix_unbranded_unknown_machine.succeed("hostname").strip()
    assert hostname == "securix-unbranded-unknown-machine", f"unexpected hostname: {hostname!r}"
  '';
}
