# SPDX-FileCopyrightText: 2026 Mattias Kockum <mattias@kockum.net>
#
# SPDX-License-Identifier: MIT
#
# Netbird fields of a VPN profile. Consumed by
# modules/vpn/netbird/default.nix, which instantiates one Netbird client per
# (operator, profile) pair. Everything else is handled by the upstream Netbird
# module, hence the very small surface here.

{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    management-url = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "URL of the Netbird management server this client registers against.";
      example = "https://netbird.example.gouv.fr:33073";
    };

    admin-url = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "URL of the Netbird administration dashboard.";
      example = "https://netbird.example.gouv.fr";
    };
  };
}
