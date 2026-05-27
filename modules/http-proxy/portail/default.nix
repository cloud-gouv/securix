# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, config, ... }:
let
  cfg = config.securix.http-proxy;
  automaticCfg = config.securix.automatic-http-proxy;
  inherit (lib) mkIf concatStringsSep mapAttrs concatMapAttrs;
  localProxyStream = "127.0.0.1:8080";
in
{
  imports = [ ./tray.nix ];

  config = mkIf (cfg.enable && cfg.implementation == "portail") {
    networking.proxy = {
      default = "http://${localProxyStream}";
      noProxy = concatStringsSep "," cfg.exceptions;
    };

    securix.networkmanager.events.handlers = concatMapAttrs (
      eventName:
      { matchConnectionId, proxyToActuate }:
      let
        proxyMetadata =
          automaticCfg.proxies.${proxyToActuate}
            or (throw "Proxy '${proxyToActuate}' is not defined in the list of automatically managed proxies");
      in
      {
        "${eventName}-up" = {
          event = "vpn-up";
          inherit matchConnectionId;

          script = ''
            # Hook for proxy ${proxyToActuate} related to VPN ${proxyMetadata.vpn}
            # For connection ID: ${matchConnectionId}
            logger "[Portail proxy hook] Automatically switching to proxy ${proxyToActuate}"
            ${config.services.portail.package}/bin/portail rpc set-default-backend ${proxyToActuate}
            # TODO: only run this if the auth method uses ssh tunnels.
            # TODO: use Portail's native SSH tunnels later on.
            systemctl --user -M "$user"@ stop "ssh-tunnel-to-*" --all
            systemctl --user -M "$user"@ start ssh-tunnel-to-${proxyToActuate}.service
          '';
        };

        "${eventName}-down" = {
          event = "vpn-down";
          inherit matchConnectionId;

          script = ''
            # Hook for proxy ${proxyToActuate}
            # For connection ID: ${matchConnectionId}
            logger "[Portail proxy hook] Automatically switching to no proxy"
            ${config.services.portail.package}/bin/portail rpc unset-default-backend ${proxyToActuate}
            # TODO: only run this if the auth method uses ssh tunnels.
            # TODO: use Portail's native SSH tunnels later on.
            systemctl --user -M "$user"@ stop "ssh-tunnel-to-${proxyToActuate}.service"
          '';
        };
      }
    ) automaticCfg.networkmanager.events.handlers;

    # This group is allowed to update any dynamic backend (if there's any).
    users.groups.portail-admins = { };
    services.portail = {
      enable = true;
      # First request optimization, this avoids the first request to wait for some time needlessly as Portail is pretty fast to boot.
      enableAtBoot = true;
      proxyListenStream = localProxyStream;

      acl.filter.rules."99-default" = ''
        policy default {
          action allow
        }
      '';

      settings = {
        # By default, we use ourselves to exit.
        backends = mapAttrs (name: target-address: { inherit target-address; }) cfg.downstreams;
        rpc = {
          trusted-groups = [ "operator" ];
          admin-groups = [ "portail-admins" ];
        };
      };
    };

    systemd.services.portail.aliases = [ "http-proxy.service" ];
  };
}
