# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.securix.automatic-http-proxy;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mapAttrs
    filterAttrs
    types
    concatMapAttrs
    ;

  handlerOpts = _: {
    options = {
      matchConnectionId = mkOption {
        type = types.str;
        description = "Connection ID to match this handler with.";
        example = "VPN ipsec for jdoe";
      };
      proxyToActuate = mkOption {
        type = types.str;
        description = "Name of the proxy to actuate (turn on / turn off in response to VPN events)";
        example = "office";
      };
    };
  };

  httpProxyOpts = _: {
    options = {
      default = mkOption {
        type = types.bool;
        default = false;
        description = "Si cette option est cochée, alors ce proxy est automatiquement connecté lorsque l'interface VPN correspondante est connectée";
      };

      vpn = mkOption {
        type = types.str;
        description = "VPN requis pour ce proxy HTTP";
      };

      remote = {
        address = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Adresse IP du proxy d'accès distant";
        };

        port = mkOption {
          type = types.port;
          default = 8080;
          description = "Port du proxy d'accès distant";
        };
      };

      auth.sshForward = {
        enable = mkEnableOption ''
          l'authentification via un SSH forward

                    Le proxy d'accès se retrouve de l'autre côté de la cible SSH sans authentification.
                    La cible SSH sert alors de bastion d'authentification du proxy d'accès.
        '';

        remote = {
          address = mkOption {
            type = types.str;
            default = "127.0.0.1";
            description = "Adresse IP du proxy d'accès distant";
          };

          port = mkOption {
            type = types.port;
            default = 8080;
            description = "Port du proxy d'accès distant";
          };
        };

        target = mkOption {
          type = types.str;
          description = "Cible SSH qui permet d'exposer le proxy d'accès distant";
        };
      };
    };
  };

  mkSSHTunnel =
    proxyName:
    {
      auth,
      remote,
      vpn,
      ...
    }:
    {
      enable = true;
      inherit (auth.sshForward) target;
      inherit vpn;
      description = "Tunnel SSH vers un proxy d'accès (${proxyName})";
      localPort = remote.port;
      remoteAddress = auth.sshForward.remote.address;
      remotePort = auth.sshForward.remote.port;
    };
in
{
  options.securix.automatic-http-proxy = {
    enable = mkEnableOption "configure des proxies HTTP automatiquement";

    proxies = mkOption { type = types.attrsOf (types.submodule httpProxyOpts); };
    networkmanager.events.handlers = mkOption { type = types.attrsOf (types.submodule handlerOpts); };
  };

  config = mkIf cfg.enable {
    securix.http-proxy = {
      enable = true;

      downstreams = mapAttrs (
        _: { remote, ... }: "${remote.address}:${toString remote.port}"
      ) cfg.proxies;
    };

    securix.networkmanager.events.handlers = concatMapAttrs (
      eventName:
      { matchConnectionId, proxyToActuate }:
      let
        proxyMetadata =
          cfg.proxies.${proxyToActuate}
            or (throw "Proxy '${proxyToActuate}' is not defined in the list of automatically managed proxies");
      in
      {
        "${eventName}-up" = {
          event = "vpn-up";
          inherit matchConnectionId;

          script = ''
            # Hook for proxy ${proxyToActuate} related to VPN ${proxyMetadata.vpn}
            # For connection ID: ${matchConnectionId}
            logger "[Generic proxy hook] Automatically switching to proxy ${proxyToActuate}"
            ${pkgs.proxy-switcher}/bin/proxy-switcher ${proxyToActuate} --cli
            # TODO: only run this if the auth method uses ssh tunnels.
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
            logger "[Generic proxy hook] Automatically switching to no proxy"
            ${pkgs.proxy-switcher}/bin/proxy-switcher np
            # TODO: only run this if the auth method uses ssh tunnels.
            systemctl --user -M "$user"@ stop "ssh-tunnel-to-${proxyToActuate}.service"
          '';
        };
      }
    ) cfg.networkmanager.events.handlers;

    securix.ssh-tunnels = mapAttrs mkSSHTunnel (
      filterAttrs (_: { auth, ... }: auth.sshForward.enable) cfg.proxies
    );
  };
}
