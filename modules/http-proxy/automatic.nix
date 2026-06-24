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
    mapAttrsToList
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

      definition = mkOption {
        type = types.enum [ "static" "dynamic" ];
        default = "static";
        description = ''
          Si la définition est statique, `remote` doit etre donné,
          sinon `remotePath` doit etre donné et doit contenir `ADDRESS` et `PORT` sous la forme suivante:

          ADDRESS="..."
          PORT="..."
        '';
      };

      remote = {
        address = mkOption {
          type = types.nullOr types.str;
          default = if definition == "127.0.0.1" then 8080 else null;
          description = "Adresse IP du proxy d'accès distant";
        };

        port = mkOption {
          type = types.nullOr types.port;
          default = if definition == "static" then 8080 else null;
          description = "Port du proxy d'accès distant";
        };
      };

      remotePath = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Chemin vers les définitions d'adresse et de port du proxy d'accès distant.
          Le fichier doit etre au format:

          ADDRESS="..."
          PORT="..."

          de sorte à ce qu'un interpréteur Bash puisse charger les variables.
        '';
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

  mkDefinitionAssert = { name, definition, remote }: {
    assertion = definition == "static" -> remote.address != null && remote.port != null;
    message = ''
      Upstream `${name}` is defined as a static proxy but its remote information is not specified.
      Either use `definition = "dynamic";` to load its definition at runtime or specify `remote = { address = "..."; port = "..."; };`
    '';
  };
in
{
  options.securix.automatic-http-proxy = {
    enable = mkEnableOption "configure des proxies HTTP automatiquement";

    implementation = mkOption {
      type = types.enum [
        "g3proxy"
        "portail"
      ];
      default = "g3proxy";
    };

    proxies = mkOption { type = types.attrsOf (types.submodule httpProxyOpts); };
  };

  config = mkIf cfg.enable {
    assertions = mapAttrsToList (name: { definition, remote, ... }: mkDefinitionAssert { inherit name definition remote; }) cfg.proxies;

    securix.http-proxy = {
      enable = true;

      inherit (cfg) implementation;

      downstreams = mapAttrs (
        _: { definition, remote, ... }: if definition == "static" then "${remote.address}:${toString remote.port}" else null
      ) cfg.proxies;
    };

    securix.ssh-tunnels = mapAttrs mkSSHTunnel (
      filterAttrs (_: { auth, ... }: auth.sshForward.enable) cfg.proxies
    );
  };
}
