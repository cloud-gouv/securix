# SPDX-FileCopyrightText: 2026 Mattias Kockum <mattias@kockum.net>
#
# SPDX-License-Identifier: MIT
#
# Declarative description of the VPN profiles available to an edition.
#
# A profile describes a tunnel from the infrastructure's point of view: where
# the gateway is, which cryptography to use, which subnets sit behind it, how to
# authenticate. It is shared by every agent. What turns a profile into actual
# configuration is an operator listing it in securix.self.user.allowedVPNs.
# The per-stack modules under modules/vpn/ perform that join.

{ config, lib, ... }:
let
  inherit (lib) mkOption types;

  profileModule = {
    imports = [
      ./ipsec.nix
      ./netbird.nix
      ./wireguard.nix
    ];

    options.type = mkOption {
      type = types.enum [
        "ipsec"
        "netbird"
        "wireguard"
      ];
      description = ''
        VPN stack backing this profile. It selects which module renders the
        profile into configuration, and which of the fields below are used.
      '';
    };

    options.mkAddress = mkOption {
      type = types.nullOr (types.functionTo types.str);
      default = null;
      defaultText = lib.literalExpression "null";
      description = ''
        Function mapping an operator's {option}`securix.self.user.bit` to their
        address inside the tunnel, in CIDR notation. Shared by the IPsec and
        WireGuard stacks. For IPsec it must be left unset when
        {option}`localSubnet` is `%any`, since the gateway then assigns the
        address itself.
      '';
      example = lib.literalExpression ''bit: "10.42.0.''${toString bit}/32"'';
    };
  };

  requiredFields = {
    ipsec = [
      "endpoint"
      "esp"
      "ike"
      "localSubnet"
      "method"
      "remoteSubnets"
    ];
    netbird = [
      "admin-url"
      "management-url"
    ];
    wireguard = [
      "agePivSlot"
      "interface"
      "listenPort"
      "mkAddress"
      "peers"
      "wireguardPivSlot"
    ];
  };
in
{
  options.securix.vpn.profiles = mkOption {
    type = types.attrsOf (types.submodule profileModule);
    default = { };
    description = ''
      VPN profiles available to this edition, keyed by profile name. Operators
      opt into them through {option}`securix.self.user.allowedVPNs`.
    '';
    example = lib.literalExpression ''
      {
        vpn-01 = {
          type = "ipsec";
          endpoint = "vpn.example.gouv.fr";
          remote-identity = "CN=vpn.example.gouv.fr";
          method = "cert-on-security-token";
          ike = "aes256gcm16-prfsha384-ecp384";
          esp = "aes256gcm16-ecp384";
          remoteSubnets = [ "10.10.0.0/16" ];
          localSubnet = "%any";
        };
      }
    '';
  };

  config.assertions = lib.concatLists (
    lib.mapAttrsToList (
      profileName: profile:
      map (field: {
        assertion = profile.${field} != null;
        message = "VPN profile `${profileName}` is of type `${profile.type}` and must therefore set `${field}`.";
      }) requiredFields.${profile.type}
    ) config.securix.vpn.profiles
  );
}
