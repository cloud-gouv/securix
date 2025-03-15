# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  vpnProfiles,
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.securix.vpn.netbird;
  inherit (lib)
    mkIf
    mkEnableOption
    listToAttrs
    concatMapAttrs
    filter
    hasAttr
    ;
  selectNetbirdVpns =
    list:
    filter (vpnName: hasAttr vpnName vpnProfiles && vpnProfiles.${vpnName}.type == "netbird") list;
in
{
  options.securix.vpn.netbird = {
    enable = mkEnableOption "the Netbird VPN subsystem";

    enablePostQuantumCryptography = mkEnableOption "the post-quantum cryptography in WireGuard with Rosenpass";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      netbird
      netbird-ui
    ];

    services.netbird = {
      enable = lib.mkForce false;
      clients = concatMapAttrs (
        operatorName:
        { allowedVPNs, ... }:
        listToAttrs (
          map (
            vpnName:
            let
              vpnProfile = vpnProfiles.${vpnName};
            in
            {
              name = "${operatorName}-${vpnName}";
              value = {
                ui.enable = true;
                interface = "nb-${vpnName}";
                port = 51820;
                hardened = false;
                config = {
                  ManagementURL = vpnProfile.management-url;
                  AdminURL = vpnProfile.admin-url;
                  RosenpassEnabled = cfg.enablePostQuantumCryptography;
                };
              };
            }
          ) (selectNetbirdVpns allowedVPNs)
        )
      ) config.securix.users.allowedUsers;
    };
  };
}
