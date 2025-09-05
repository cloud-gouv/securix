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
    ;

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

        localPort = mkOption {
          type = types.port;
          description = "Port local du proxy d'accès distant après SSH forward";
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
      description = "Tunnel SSH vers un proxy d'accès (${proxyName})";
      inherit (auth.sshForward) target localPort;
      inherit vpn;
      remoteAddress = remote.address;
      remotePort = remote.port;
    };
in
{
  options.securix.automatic-http-proxy = {
    enable = mkEnableOption "configure des proxies HTTP automatiquement";

    proxies = mkOption { type = types.attrsOf (types.submodule httpProxyOpts); };
  };

  config = mkIf cfg.enable {
    securix.http-proxy = {
      enable = true;

      downstreams = mapAttrs (
        _: { remote, ... }: "${remote.address}:${toString remote.port}"
      ) cfg.proxies;
    };

    securix.ssh-tunnels = mapAttrs mkSSHTunnel (
      filterAttrs (_: { auth, ... }: auth.sshForward.enable) cfg.proxies
    );
  };
}
