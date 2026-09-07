# SPDX-FileCopyrightText: 2026 Mattias Kockum <mattias@kockum.net>
#
# SPDX-License-Identifier: MIT
#
# Shared fixtures and checks for the VPN profile tests.

{ pkgs }:
let
  inherit (pkgs) lib;
in
rec {
  vpnProfiles = {
    ipsec-01 = {
      type = "ipsec";
      endpoint = "vpn-01.example.gouv.fr";
      remote-identity = "CN=vpn-01.example.gouv.fr";
      method = "psk";
      ike = "aes256gcm16-prfsha384-ecp384";
      esp = "aes256gcm16-ecp384";
      remoteSubnets = [ "10.10.0.0/16" ];
      localSubnet = "10.42.0.0/24";
      gateway = "10.42.0.254";
      dns = "10.10.0.53";
      mkAddress = bit: "10.42.0.${toString bit}/32";
      mkPasswordVariable = operator: "$IPSEC_PSK_${lib.toUpper operator}";
    };

    wg-01 = {
      type = "wireguard";
      interface = "wg-01";
      listenPort = 51821;
      wireguardPivSlot = "0x5fc10d";
      agePivSlot = 10;
      mkAddress = bit: "10.43.0.${toString bit}/32";
      peers = [
        {
          publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          endpoint = "wg-01.example.gouv.fr:51820";
          ips = [ "10.43.0.0/24" ];
        }
      ];
    };

    ipsec-02 = {
      type = "ipsec";
      endpoint = "vpn-02.example.gouv.fr";
      remote-identity = "CN=vpn-02.example.gouv.fr";
      method = "psk";
      ike = "aes256gcm16-prfsha384-ecp384";
      esp = "aes256gcm16-ecp384";
      remoteSubnets = [ "10.20.0.0/16" ];
      localSubnet = "%any";
      mkPasswordVariable = operator: "$IPSEC_PSK_02_${lib.toUpper operator}";
    };
  };

  alice = {
    securix.self.user = {
      username = "alice";
      email = "alice@example.gouv.fr";
      hashedPassword = "$y$j9T$zk4xGLyshz7RzqnMX6M8O0$AybRelILMkQSWcQZV4s.ykRNi/UlgaCUaDwdee0n7N2";
      bit = 12;
      allowedVPNs = [
        "ipsec-01"
        "wg-01"
      ];
    };
  };

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

  baseModule = {
    users.allowNoPasswordLogin = true;
    securix = {
      graphical-interface.variant = "sway";
      users.allowAnyOperator = true;
      vpn = {
        ipsec.enable = true;
        wireguard.enable = true;
      };
    };
  };

  mkChecks =
    terminal:
    let
      cfg = terminal.system.config;
      nmProfiles = cfg.networking.networkmanager.ensureProfiles.profiles;
      alicePackageNames = map (p: p.name) cfg.users.users.alice.packages;
      sudoCommands = lib.concatMap (rule: map (c: c.command or c) rule.commands) (
        lib.filter (rule: rule.users or [ ] != [ ]) cfg.security.sudo.extraRules
      );
    in
    {
      "the resulting system evaluates end to end" = lib.isString cfg.system.build.toplevel.drvPath;

      "ipsec-01 yields a NetworkManager profile for alice" = nmProfiles ? "alice-ipsec-01";
      "ipsec-02 yields nothing since it is not in allowedVPNs" = !(nmProfiles ? "alice-ipsec-02");
      "wg-01 yields NO NetworkManager profile" = !(nmProfiles ? "alice-wg-01");
      "no other NetworkManager profile is generated" = lib.attrNames nmProfiles == [ "alice-ipsec-01" ];

      "endpoint becomes vpn.address" = nmProfiles.alice-ipsec-01.vpn.address == "vpn-01.example.gouv.fr";
      "remoteSubnets becomes remote-ts" = nmProfiles.alice-ipsec-01.vpn.remote-ts == "10.10.0.0/16";
      "mkAddress is applied to the operator bit" =
        nmProfiles.alice-ipsec-01.vpn.local-ts == "10.42.0.12/32";
      "manual addressing combines mkAddress and gateway" =
        nmProfiles.alice-ipsec-01.ipv4.address1 == "10.42.0.12/32,10.42.0.254";
      "the psk method is carried over to the connection" = nmProfiles.alice-ipsec-01.vpn.method == "psk";
      "mkPasswordVariable yields the secret variable reference" =
        nmProfiles.alice-ipsec-01.vpn-secrets.password == "$IPSEC_PSK_ALICE";
      "ipv6 is disabled" = nmProfiles.alice-ipsec-01.ipv6.method == "disabled";

      "the connection is locked to its user" =
        nmProfiles.alice-ipsec-01.connection.permissions == "user:alice;";
      "the connection id follows the expected convention" =
        nmProfiles.alice-ipsec-01.connection.id == "VPN ipsec-01 for alice";

      "the tunnel management script is installed" = lib.elem "wireguard-wg-01" alicePackageNames;
      "the key management scripts are installed" = lib.all (n: lib.elem n alicePackageNames) [
        "wireguard-wg-01-genkey"
        "wireguard-wg-01-pubkey"
        "wireguard-wg-01-importkey"
      ];
      "no script is generated for a disallowed profile" =
        !(lib.elem "wireguard-ipsec-02" alicePackageNames);

      "sudo allows driving the tunnel without a password" =
        lib.elem "/etc/profiles/per-user/alice/bin/wireguard-wg-01" sudoCommands;
    };

  mkTest =
    name: terminal:
    let
      failures = lib.attrNames (lib.filterAttrs (_: passed: !passed) (mkChecks terminal));
    in
    assert lib.assertMsg (failures == [ ]) ''
      VPN profile behaviour changed. Failing checks:
      ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failures}
    '';
    pkgs.runCommand name { } "touch $out";
}
