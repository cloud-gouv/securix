# SPDX-FileCopyrightText: 2026 Mattias Kockum <mattias@kockum.net>
#
# SPDX-License-Identifier: MIT
#
# Characterization test for VPN profiles.
#
# This test evaluates the configuration produced by mkTerminal
# and checks the observable artifacts,
# using the new vpn profiles modules

{ pkgs, libSecurix }:
let
  common = import ./vpn-profiles-common.nix { inherit pkgs; };
in
common.mkTest "vpn-profiles-module-refactor" (
  libSecurix.mkTerminal {
    name = "vpn-profiles";
    inherit (common) userSpecificModule;
    extraOperators = { inherit (common) alice; };
    modules = [
      common.baseModule
      { securix.vpn.profiles = common.vpnProfiles; }
    ];
  }
)
