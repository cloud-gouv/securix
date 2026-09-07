# SPDX-FileCopyrightText: 2026 Mattias Kockum <mattias@kockum.net>
#
# SPDX-License-Identifier: MIT
#
# Backwards-compatibility test for the legacy _module.args.vpnProfiles
# channel.
#
# NOTE: this test exists to protect a behaviour that will be deprecated.
# Delete it in the same commit that removes _module.args.vpnProfiles
# from lib/default.nix.

{ pkgs, libSecurix }:
let
  inherit (pkgs) lib;
  common = import ./vpn-profiles-common.nix { inherit pkgs; };

  outOfTreeConsumer = { vpnProfiles, ... }: {
    options.legacyVpnProfilesProbe = lib.mkOption {
      type = lib.types.raw;
      internal = true;
      description = "What an unmigrated module sees through _module.args.vpnProfiles.";
    };
    config.legacyVpnProfilesProbe = vpnProfiles;
  };

  terminal = libSecurix.mkTerminal {
    name = "vpn-profiles";
    inherit (common) userSpecificModule vpnProfiles;
    extraOperators = { inherit (common) alice; };
    modules = [
      common.baseModule
      outOfTreeConsumer
    ];
  };

  seen = terminal.system.config.legacyVpnProfilesProbe;

  checks = {
    "an unmigrated module still receives the profiles" =
      lib.attrNames seen == [
        "ipsec-01"
        "ipsec-02"
        "wg-01"
      ];

    "the profiles it receives carry their values" =
      (seen.ipsec-01.endpoint or null) == "vpn-01.example.gouv.fr";

    "functions survive the legacy channel" = (seen.ipsec-01.mkAddress 12) == "10.42.0.12/32";

    "the legacy channel carries the raw attribute set, not the normalized one" =
      !(seen.ipsec-01 ? interface);
  };

  failures = lib.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in
assert lib.assertMsg (failures == [ ]) ''
  The legacy `_module.args.vpnProfiles` channel no longer works for unmigrated
  modules. Failing checks:
  ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failures}
'';
pkgs.runCommand "vpn-profiles-legacy-channel" { } "touch $out"
