# SPDX-FileCopyrightText: 2026 Mattias Kockum <mattias@kockum.net>
#
# SPDX-License-Identifier: MIT
#
# Validation test for securix.self.user.allowedVPNs.

{ pkgs, libSecurix }:
let
  inherit (pkgs) lib;
  common = import ./vpn-profiles-common.nix { inherit pkgs; };

  aliceWithUnknownVpn = lib.recursiveUpdate common.alice {
    securix.self.user.allowedVPNs = [
      "ipsec-01"
      "nexistepas"
    ];
  };

  terminal = libSecurix.mkTerminal {
    name = "vpn-profiles";
    inherit (common) vpnProfiles;
    userSpecificModule = {
      imports = [ aliceWithUnknownVpn ];
      securix.self = {
        mainDisk = "/dev/nvme0n1";
        machine = {
          hardwareSKU = "x280";
          inventoryId = 0;
        };
      };
    };
    extraOperators = {
      alice = aliceWithUnknownVpn;
    };
    modules = [ common.baseModule ];
  };

  failedAssertions = lib.filter (a: !a.assertion) terminal.system.config.assertions;
  messages = lib.concatStringsSep "\n" (map (a: a.message) failedAssertions);

  checks = {
    "referencing an unknown VPN raises exactly one assertion" = lib.length failedAssertions == 1;
    "the assertion names the offending VPN" = lib.hasInfix "nexistepas" messages;
    "the assertion names the offending user" = lib.hasInfix "alice" messages;
    "a known VPN raises nothing" = !(lib.hasInfix "ipsec-01" messages);
  };

  failures = lib.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in
assert lib.assertMsg (failures == [ ]) ''
  `allowedVPNs` is no longer validated as expected. Failing checks:
  ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failures}

  Assertions actually raised:
  ${messages}
'';
pkgs.runCommand "vpn-profiles-validation" { } "touch $out"
