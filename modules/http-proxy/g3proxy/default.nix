# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (lib)
    mkIf
    concatStringsSep
    tail
    splitString
    concatMapAttrs
    mapAttrsToList
    ;
  json = pkgs.formats.json { };
  cfg = config.securix.http-proxy;
  automaticCfg = config.securix.automatic-http-proxy;
  proxyConfigFile = json.generate "proxies.json" cfg.downstreams;
in
{
  config = mkIf (cfg.enable && cfg.implementation == "g3proxy") {
    assertions = mapAttrsToList (name: { definition, ... }: {
      assertion = definition == "static";
      message = "Upstream proxy ${name} is not marked as a static proxy. The g3proxy implementation do not support dynamically defined proxies like Portail does.";
    }) config.securix.automatic-http-proxy.proxies;

    networking.proxy = {
      default = "http://127.0.0.1:8080";
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
    ) automaticCfg.networkmanager.events.handlers;

    nixpkgs.overlays = [
      (self: super: {
        proxy-switcher = pkgs.writeShellApplication {
          name = "proxy-switcher";
          # disables shellcheck.
          checkPhase = "";
          runtimeEnv = {
            EXTRA_ENV_FILE = cfg.secretsPath;
          };
          text =
            let
              noShebang = concatStringsSep "\n" (tail (splitString "\n" (builtins.readFile ./proxy-switcher.sh)));
            in
            noShebang;
          runtimeInputs = [
            # for g3proxy-ctl
            pkgs.g3proxy
            pkgs.jq
            # For whiptail.
            pkgs.newt
            # For notify user
            pkgs.gawk
            pkgs.libnotify
            pkgs.sudo
            pkgs.gettext
          ];
        };

        current-proxy = pkgs.writeShellApplication {
          name = "current-proxy";
          # disables shellcheck
          checkPhase = "";
          runtimeEnv = {
            EXTRA_ENV_FILE = cfg.secretsPath;
          };
          text =
            let
              noShebang = concatStringsSep "\n" (tail (splitString "\n" (builtins.readFile ./current-proxy.sh)));
            in
            noShebang;
          runtimeInputs = [ pkgs.gettext ];
        };
      })
    ];

    environment.etc."proxy-switcher/proxies.json".source = proxyConfigFile;
    environment.systemPackages = [
      pkgs.g3proxy
      pkgs.proxy-switcher
      pkgs.current-proxy
    ];

    security.sudo = {
      enable = true;
      extraRules = [
        {
          groups = [ "operator" ];
          commands = [
            {
              command = "/run/current-system/sw/bin/proxy-switcher";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/current-proxy";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };

    # Static allocation of UID/GID for g3proxy.
    # Necessary to perform the nftables rule targeting.
    ids.uids.g3proxy = 398;
    ids.gids.g3proxy = 398;

    users.users.g3proxy = {
      isSystemUser = true;
      uid = config.ids.uids.g3proxy;
      group = "g3proxy";
    };

    users.groups.g3proxy = {
      gid = config.ids.gids.g3proxy;
    };

    services.g3proxy = {
      enable = true;
      settings = {
        resolver = [
          {
            name = "default";
            type = "c-ares";
            # DNS4EU co-funded by European Union initiative.
            # https://www.joindns4.eu/learn/dns4eu-public-service-launched
            server = [
              "86.54.11.1"
              "86.54.11.201"
            ];
          }
        ];

        escaper = [
          # Link the default escaper to the special internal HTTP proxy.
          {
            name = "default";
            type = "direct_fixed";
            no_ipv6 = false;
            resolver = "default";
          }

          # This is the dynamic escaper where a couple of proxies
          # can be set via the proxy-switcher dynamically over Cap'n'Proto RPC.
          {
            name = "dynamic";
            type = "proxy_float";
            source.type = "passive";
            cache = "/tmp/current-proxy.json";
          }
        ];

        server = [
          # This is the fallback local forward proxy.
          # Used for network locations with no forward proxy.
          {
            name = "local_securix";
            escaper = "default";
            # TODO: intelli_proxy here.
            type = "http_proxy";
            listen.address = "127.0.0.1:8081";
            tls_client = { };
            dst_host_filter_set = cfg.noProxyAllowedHosts;
          }

          # This is the entrypoint of all proxy requests.
          {
            name = "securix";
            escaper = "dynamic";
            # TODO: intelli_proxy here.
            type = "http_proxy";
            listen.address = "127.0.0.1:8080";
            tls_client = { };
            # dst_host_filter_set = {
            #   exact = nonSubnetsExceptions ++ domainsExceptions;
            #   child = domainsExceptions;
            #   regex = domainsExceptions;
            #   subnet = subnetsExceptions;
            # };
          }
        ];
      };
    };

    systemd.services.g3proxy.aliases = [ "http-proxy.service" ];
  };
}
