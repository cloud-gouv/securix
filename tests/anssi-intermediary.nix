# SPDX-FileCopyrightText: 2026 Sébastien Celles <s.celles@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# Regression test for https://github.com/cloud-gouv/securix/issues/286 and
# https://github.com/cloud-gouv/securix/issues/293: with the `intermediary`
# level, reverse path filtering is strict on every interface and
# `anssi-nixos-compliance-check` colours rules from their exit status.

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
      users.users.alice = {
        isNormalUser = true;
        hashedPassword = "!";
      };
    };
  };
  testScript = ''
    import re

    machine = securix_unbranded_0
    machine.wait_for_unit("default.target")

    def colours(output):
        # rule id -> ANSI colour code of its line
        return {
            m.group(2): m.group(1)
            for m in re.finditer(r"\x1b\[(\d+)m(R\d+)\S*\s+:", output)
        }

    with subtest("Reverse path filtering is strict on every interface (#286)"):
        values = machine.succeed("grep . /proc/sys/net/ipv4/conf/*/rp_filter")
        print(values)
        assert all(line.endswith(":1") for line in values.split()), values
        machine.succeed("test \"$(sysctl -n net.ipv4.conf.all.accept_source_route)\" = 0")
        machine.succeed("test \"$(sysctl -n net.ipv4.conf.default.accept_source_route)\" = 0")

    with subtest("Rules are coloured from their exit status (#286, #293)"):
        out = machine.succeed("anssi-nixos-compliance-check")
        print(out)
        c = colours(out)
        # R12 passes; its output contains "icmp_ignore_bogus_error_responses".
        assert c.get("R12") == "32", c
        # R2 and R5 are not implemented.
        assert c.get("R2") == "33", c
        assert c.get("R5") == "33", c

    with subtest("An unreadable sysctl is reported as such (#286)"):
        out = machine.succeed("su - alice -c anssi-nixos-compliance-check")
        print(out)
        assert colours(out).get("R12") == "31", out
        assert "unable to read sysctl value" in out, out
  '';
}
