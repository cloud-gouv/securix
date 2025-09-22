# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  pkgs,
  lib,
  config,
  ...
}@args:
let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkMerge
    types
    concatStringsSep
    tail
    splitString
    ;
  json = pkgs.formats.json { };
  cfg = config.securix.http-proxy;
  proxyConfigFile = json.generate "proxies.json" cfg.downstreams;

  securix-lib = import ../../lib/utils.nix args;

  subnetsExceptions = lib.filter (
    address:
    (securix-lib.address.isIPv4WithSubnet address) || (securix-lib.address.isIPv6WithSubnet address)
  ) cfg.exceptions;
  nonSubnetsExceptions = lib.filter (
    address:
    (securix-lib.address.isIPv4WithoutSubnet address)
    || (securix-lib.address.isIPv6WithoutSubnet address)
  ) cfg.exceptions;
  domainsExceptions = lib.filter (
    address: !((securix-lib.address.isIPv4 address) || (securix-lib.address.isIPv6 address))
  ) cfg.exceptions;
in
{
  options.securix.http-proxy = {
    enable = mkEnableOption "configure un proxy HTTP client SOCKS5 globalement";

    downstreams = mkOption {
      type = types.attrsOf types.str;
      example = [
        {
          par_a = "1.2.3.4:8080";
          par_b = "1.5.6.8:8080";
          rbx_a = "1.8.9.2:9091";
        }
      ];
      description = "Ensembles des proxies descendants";
    };

    exceptions = mkOption {
      type = types.listOf types.str;
      # Exclude localhost and its IP variants for now.
      default = [
        "localhost"
        "127.0.0.1"
        "[::1]"
      ];
      description = "Liste de domaines exclus du proxy";
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      networking.proxy = {
        default = "http://127.0.0.1:8080";
        noProxy = concatStringsSep "," cfg.exceptions;
      };

      nixpkgs.overlays = [
        (self: super: {
          proxy-switcher = pkgs.writeShellApplication {
            name = "proxy-switcher";
            # disables shellcheck.
            checkPhase = "";
            text =
              let
                noShebang = concatStringsSep "\n" (tail (splitString "\n" (builtins.readFile ./proxy-switcher.sh)));
              in
              noShebang;
            runtimeInputs = [
              # for g3proxy-ctl
              config.services.g3proxy.package
              pkgs.jq
              # For whiptail.
              pkgs.newt
              # For notify user
              pkgs.gawk
              pkgs.libnotify
              pkgs.sudo
            ];
          };

          current-proxy = pkgs.writeShellApplication {
            name = "current-proxy";
            # disables shellcheck.
            checkPhase = "";
            text =
              let
                noShebang = concatStringsSep "\n" (tail (splitString "\n" (builtins.readFile ./current-proxy.sh)));
              in
              noShebang;
            runtimeInputs = [
              # for g3proxy-ctl
              # config.services.g3proxy.package
              # pkgs.jq
              # For whiptail.
              # pkgs.newt
            ];
          };

        })
      ];

      environment.etc."proxy-switcher/proxies.json".source = proxyConfigFile;
      environment.systemPackages = [
        config.services.g3proxy.package
        pkgs.proxy-switcher
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
                "86.54.11.11"
                "86.54.11.211"
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
    })
  ];
}
