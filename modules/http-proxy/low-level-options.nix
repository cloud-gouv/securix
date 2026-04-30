# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.securix.http-proxy = {
    enable = mkEnableOption "configure un proxy HTTP client SOCKS5 globalement";

    implementation = mkOption {
      type = types.enum [
        "g3proxy"
        "portail"
      ];
      default = "g3proxy";
      description = ''
        Implémentation du proxy HTTP client système.
        portail est une nouvelle option expérimentale.
      '';
    };

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

    secretsPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Chemin vers vers les secrets injectés dans les scripts de gestion de proxy";
    };

    noProxyAllowedHosts = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = { };
      example = [
        {
          exact = [ "allowed-domain.example.com" ];
          child = [ "allowed-all-subdomain.example.com" ];
          regex = [ "allowed-*.example.com" ];
          subnet = [ "10.0.0.0/16" ];
        }
      ];
      description = ''
        Liste des hôtes ou réseaux autorisés sans proxy distant.
        Chaque clé représente un type de correspondance :
        - `exact` : domaines exacts.
        - `child` : domaines et tous leurs sous-domaines.
        - `regex` : expressions régulières pour les domaines.
        - `subnet` : sous-réseaux IP au format CIDR.

        Exemple : { exact = [ "exemple.com" ]; subnet = [ "192.168.1.0/24" ]; }
      '';
    };
  };

}
