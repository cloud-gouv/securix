# SPDX-FileCopyrightText: 2026 Mattias Kockum <mattias@kockum.net>
#
# SPDX-License-Identifier: MIT
#
# WireGuard fields of a VPN profile. Consumed by
# modules/vpn/wireguard/default.nix, which renders each (operator, profile)
# pair into per-user scripts rather than a systemd unit: the private key lives
# encrypted inside the agent's security token, so bringing the tunnel up
# requires their physical presence.

{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    interface = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Name of the network interface created for this tunnel.";
      example = "wg-01";
    };

    listenPort = mkOption {
      type = types.nullOr types.port;
      default = null;
      description = "Local UDP port the tunnel listens on.";
      example = 51820;
    };

    wireguardPivSlot = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        PIV object slot on the security token holding the age-encrypted
        WireGuard private key.
      '';
      example = "0x5fc10d";
    };

    agePivSlot = mkOption {
      type = types.nullOr (types.either types.int types.str);
      default = null;
      description = ''
        PIV slot holding the age identity used to decrypt the WireGuard private
        key stored in {option}`wireguardPivSlot`.
      '';
      example = 10;
    };

    peers = mkOption {
      default = null;
      description = "Remote peers of this tunnel.";
      type = types.nullOr (
        types.listOf (
          types.submodule {
            options = {
              publicKey = mkOption {
                type = types.str;
                description = "Base64-encoded public key of the peer.";
              };

              endpoint = mkOption {
                type = types.str;
                description = ''
                  Reachable address of the peer, as `host:port`. A host route
                  towards it is added through the default gateway when the
                  tunnel comes up.
                '';
                example = "wg-01.example.gouv.fr:51820";
              };

              ips = mkOption {
                type = types.listOf types.str;
                description = ''
                  Subnets routed towards this peer, in CIDR notation. Used both
                  as the peer's allowed IPs and to install routes on the tunnel
                  interface.
                '';
                example = [ "10.43.0.0/24" ];
              };
            };
          }
        )
      );
    };
  };
}
