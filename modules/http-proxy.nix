# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, config, ... }@args:
let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkMerge
    types
    concatStringsSep
    ;
  cfg = config.securix.http-proxy;

  securix-lib = import ../lib/utils.nix args;

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

      services.g3proxy = {
        enable = true;
        settings = {
          resolver = [
            {
              name = "default";
              type = "c-ares";
              # CloudFlare… Not optimal.
              # TODO: does the MTE have a public DNS?
              # https://www.joindns4.eu/
              # 86.54.11.100 (unfiltered resolver)
              server = "86.54.11.100";
              # By default, always use secure resolution. Never leak any metadata to upstream DNS servers.
              # encryption = "dns-over-https";
            }
          ];

          escaper = [
            {
              name = "default";
              type = "direct_fixed";
              no_ipv6 = false;
              resolver = "default";
            }
          ];

          server = [
            {
              name = "securix";
              escaper = "default";
              type = "http_proxy";
              listen.address = "127.0.0.1:8080";
              tls_client = { };
              dst_host_filter_set = {
                exact = nonSubnetsExceptions ++ domainsExceptions;
                child = domainsExceptions;
                regex = domainsExceptions;
                subnet = subnetsExceptions;
              };
            }
          ];
        };
      };

      systemd.services.g3proxy.aliases = [ "http-proxy.service" ];
    })
  ];
}
