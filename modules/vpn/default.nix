# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT
{ lib, ... }: {

  imports = [
    ./ipsec
    ./netbird
    ./wireguard
  ];
  options.securix.vpn.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
  };
}
