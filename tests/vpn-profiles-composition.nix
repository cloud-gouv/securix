# SPDX-FileCopyrightText: 2026 Mattias Kockum <mattias@kockum.net>
#
# SPDX-License-Identifier: MIT
#
# Composition test for securix.vpn.profiles.
#
# The other vpn tests show that the refactor breaks nothing.
# This one shows what it buys: profiles are now ordinary configuration,
# so several modules can each contribute their own, and any machine can
# override one field of one profile.

{ pkgs, libSecurix }:
let
  inherit (pkgs) lib;
  common = import ./vpn-profiles-common.nix { inherit pkgs; };

  stagingEndpoint = "vpn-01-staging.example.gouv.fr";

  alice = lib.recursiveUpdate common.alice {
    securix.self.user.allowedVPNs = [
      "ipsec-01"
      "ipsec-legal"
    ];
  };

  editionModule = {
    securix.vpn.profiles = { inherit (common.vpnProfiles) ipsec-01 wg-01; };
  };

  legalTeamModule = {
    securix.vpn.profiles.ipsec-legal = {
      type = "ipsec";
      endpoint = "vpn-legal.example.gouv.fr";
      remote-identity = "CN=vpn-legal.example.gouv.fr";
      method = "psk";
      ike = "aes256gcm16-prfsha384-ecp384";
      esp = "aes256gcm16-ecp384";
      remoteSubnets = [ "10.30.0.0/16" ];
      localSubnet = "10.44.0.0/24";
      gateway = "10.44.0.254";
      mkAddress = bit: "10.44.0.${toString bit}/32";
      mkPasswordVariable = operator: "$IPSEC_PSK_LEGAL_${lib.toUpper operator}";
    };
  };

  stagingOverrideModule = {
    securix.vpn.profiles.ipsec-01.endpoint = lib.mkForce stagingEndpoint;
  };

  terminal = libSecurix.mkTerminal {
    name = "vpn-profiles";
    userSpecificModule = {
      imports = [ alice ];
      securix.self = {
        mainDisk = "/dev/nvme0n1";
        machine = {
          hardwareSKU = "x280";
          inventoryId = 0;
        };
      };
    };
    extraOperators = { inherit alice; };
    modules = [
      common.baseModule
      editionModule
      legalTeamModule
      stagingOverrideModule
    ];
  };

  cfg = terminal.system.config;
  nmProfiles = cfg.networking.networkmanager.ensureProfiles.profiles;

  checks = {
    "the edition profile is rendered" = nmProfiles ? "alice-ipsec-01";
    "the team profile is rendered too" = nmProfiles ? "alice-ipsec-legal";
    "the team profile carries its own values" =
      (nmProfiles.alice-ipsec-legal.vpn.address or null) == "vpn-legal.example.gouv.fr";
    "a profile nobody is entitled to is still not rendered" = !(nmProfiles ? "alice-wg-01");

    "the overridden field takes the machine's value" =
      (nmProfiles.alice-ipsec-01.vpn.address or null) == stagingEndpoint;
    "the fields around it are untouched" =
      (nmProfiles.alice-ipsec-01.vpn.remote-ts or null) == "10.10.0.0/16"
      && (nmProfiles.alice-ipsec-01.ipv4.address1 or null) == "10.42.0.12/32,10.42.0.254";

    "both profiles are visible in the option" =
      lib.attrNames cfg.securix.vpn.profiles == [
        "ipsec-01"
        "ipsec-legal"
        "wg-01"
      ];
  };

  failures = lib.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in
assert lib.assertMsg (failures == [ ]) ''
  VPN profiles no longer compose as expected. Failing checks:
  ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failures}
'';
pkgs.runCommand "vpn-profiles-composition" { } "touch $out"
