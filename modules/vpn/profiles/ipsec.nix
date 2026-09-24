# SPDX-FileCopyrightText: 2026 Mattias Kockum <mattias@kockum.net>
#
# SPDX-License-Identifier: MIT
#
# IPsec/IKEv2 fields of a VPN profile. Consumed by
# modules/vpn/ipsec/networkmanager.nix, which renders each (operator, profile)
# pair into a declarative NetworkManager connection.

{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    endpoint = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Address of the IPsec gateway. Becomes `vpn.address`.";
      example = "vpn.example.gouv.fr";
    };

    remote-identity = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Identity the gateway is expected to present, used to validate its
        certificate. Left unset, NetworkManager falls back to its own default.
      '';
      example = "CN=vpn.example.gouv.fr";
    };

    method = mkOption {
      type = types.nullOr (
        types.enum [
          "cert-on-security-token"
          "psk"
        ]
      );
      default = null;
      description = ''
        Authentication method. `cert-on-security-token` drives the connection
        through the agent's smartcard and asks for its PIN; `psk` reads a
        pre-shared key from the environment variable named by
        {option}`mkPasswordVariable`.
      '';
    };

    ike = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "IKE (phase 1) cryptographic proposal.";
      example = "aes256gcm16-prfsha384-ecp384";
    };

    esp = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "ESP (phase 2) cryptographic proposal.";
      example = "aes256gcm16-ecp384";
    };

    remoteSubnets = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      description = ''
        Subnets reachable through the tunnel. Becomes the remote traffic
        selectors, and feeds the generated network flow documentation.
      '';
      example = [ "10.10.0.0/16" ];
    };

    localSubnet = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Subnet the agent belongs to inside the tunnel. The special value `%any`
        switches the connection to IPsec config mode, where the gateway assigns
        the address; in that case {option}`mkAddress` and {option}`gateway` must
        be left unset.
      '';
      example = "%any";
    };

    gateway = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Gateway address inside the tunnel, for manual addressing. Must be unset
        when {option}`localSubnet` is `%any`.
      '';
    };

    dns = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "DNS server to use while the tunnel is up.";
    };

    mkPasswordVariable = mkOption {
      type = types.nullOr (types.functionTo types.str);
      default = null;
      defaultText = lib.literalExpression "null";
      description = ''
        Function mapping an operator name to the shell variable holding their
        pre-shared key. The generated connection file is piped through envsubst,
        so the returned string must keep its leading `$`. Required when
        {option}`method` is `psk`.
      '';
      example = lib.literalExpression ''operator: "\$IPSEC_PSK_''${operator}"'';
    };

    availableHttpProxies = mkOption {
      type = types.attrsOf types.raw;
      # NOTE: this one defaults to { } rather than null on purpose. The
      # consumer tests (profile.availableHttpProxies or { }) != { } to decide
      # whether to wire up proxy switching. A null default would make that
      # test true for every profile and silently enable the machinery fleet-wide.
      default = { };
      description = ''
        Deprecated. HTTP proxies to switch to when this tunnel comes up. Use
        {option}`securix.vpn.ipsec.proxies.map` or the NetworkManager event
        handlers instead.
      '';
    };
  };
}
