# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, config, ... }:
let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    concatStringsSep
    ;
  cfg = config.securix.http-proxy;
in
{
  options.securix.http-proxy = {
    enable = mkEnableOption "configure un proxy HTTP client SOCKS5 globalement";

    availableProxies = mkOption {
      type = types.attrsOf types.str;
      description = "Liste des proxies SOCKS5 disponibles";
    };

    usedProxy = mkOption {
      type = types.str;
      description = "Proxy sélectionné";
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

    usedProxyAddress = mkOption {
      type = types.str;
      readOnly = true;
      internal = true;
      description = "Adresse du proxy séléctionné";
    };
  };

  config = mkIf cfg.enable {
    securix.http-proxy.usedProxyAddress = cfg.availableProxies.${cfg.usedProxy};
    environment.sessionVariables = {
      all_proxy = cfg.usedProxyAddress;
      http_proxy = cfg.usedProxyAddress;
      https_proxy = cfg.usedProxyAddress;
      no_proxy = concatStringsSep "," cfg.exceptions;
    };
  };
}
