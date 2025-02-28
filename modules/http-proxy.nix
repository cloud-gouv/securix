# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
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
  selectedProxy = cfg.availableProxies.${cfg.usedProxy};
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
  };

  config = mkIf cfg.enable {
    environment.sessionVariables = {
      all_proxy = selectedProxy;
      http_proxy = selectedProxy;
      https_proxy = selectedProxy;
      no_proxy = concatStringsSep "," cfg.exceptions;
    };
  };
}
