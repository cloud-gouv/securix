# SPDX-FileCopyrightText: 2026 Sébastien Celles <s.celles@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# Regression test for https://github.com/cloud-gouv/securix/issues/286:
# with the `intermediary` level, reverse path filtering is strict on every
# interface.

{ pkgs, libSecurix }:
let
  terminal = libSecurix.mkTerminal {
    name = "anssi-intermediary";
    userSpecificModule = { };
    vpnProfiles = { };
    modules = [
      {
        security.anssi = {
          enable = true;
          level = "intermediary";
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
  name = "anssi-intermediary";
  nodes = {
    securix-unbranded-0 = {
      imports = terminal.modules;
    };
  };
  testScript = ''
    machine = securix_unbranded_0
    machine.wait_for_unit("default.target")

    with subtest("Reverse path filtering is strict on every interface"):
        values = machine.succeed("grep . /proc/sys/net/ipv4/conf/*/rp_filter")
        print(values)
        assert all(line.endswith(":1") for line in values.split()), values
        machine.succeed("test \"$(sysctl -n net.ipv4.conf.all.accept_source_route)\" = 0")
        machine.succeed("test \"$(sysctl -n net.ipv4.conf.default.accept_source_route)\" = 0")
  '';
}
