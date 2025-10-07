# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib)
    types
    mkOption
    mkEnableOption
    filterAttrs
    mapAttrs'
    nameValuePair
    ;
  tunnels = config.securix.ssh-tunnels;
  tunnelOpts = _: {
    options = {
      enable = mkEnableOption "this tunnel";
      vpn = mkOption {
        type = types.str;
        description = "VPN requis pour ce tunnel";
      };
      description = mkOption { type = types.str; };
      target = mkOption { type = types.str; };
      localPort = mkOption { type = types.int; };
      remoteAddress = mkOption {
        type = types.str;
        default = "localhost";
      };
      remotePort = mkOption { type = types.int; };
    };
  };

  mkTunnelService =
    name:
    {
      description,
      vpn,
      target,
      localPort,
      remoteAddress,
      remotePort,
      ...
    }:
    nameValuePair "ssh-tunnel-to-${name}" {
      inherit description;
      after = [ "network.target" ];

      path = [
        pkgs.libnotify
        pkgs.networkmanager
      ];
      # TODO: this is largely inefficient.
      # Diconnection of the SSH tunnel will be performed after 3 seconds of inactivity.
      script = ''
        if ! nmcli connection show --active | grep -q ${vpn}; then
          exit 1
        fi

        if ! ${pkgs.openssh}/bin/ssh -NT -o ServerAliveInterval=1 -o ExitOnForwardFailure=yes -L 127.0.0.1:${toString localPort}:${remoteAddress}:${toString remotePort} ${target}; then
          notify-send "[HTTP Proxy] Échec" "Échec de l'établissement du tunnel vers ${name} depuis ${target} ; est-ce que le VPN ou Internet est opérationnel ? Si vous utilisez un yubikey, est-ce qu'elle est branchée ? L'erreur exacte peut être vue avec journalctl."
        else
          notify-send "[HTTP Proxy] Coupé" "La connexion via SSH vers le proxy HTTP ${name} a été stoppé."
        fi
      '';

      serviceConfig = {
        RestartSec = "5";
        Restart = "always";
      };
    };
in
{
  options.securix.ssh-tunnels = mkOption {
    type = types.attrsOf (types.submodule tunnelOpts);
    default = { };
  };

  config = {
    # One per operator.
    systemd.user.services = mapAttrs' mkTunnelService (
      filterAttrs (_: { enable, ... }: enable) tunnels
    );
  };
}
