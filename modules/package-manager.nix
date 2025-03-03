# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  lib,
  config,
  pkgs,
  ...
}:
let
  proxyCfg = config.securix.http-proxy;
in
{
  config = {
    nix =
      {
        package = pkgs.lix;
        nixPath = [
          # Always point to the authorized sources.
          "nixpkgs=${pkgs.path}"
        ];
      }
      // (lib.optionalAttrs proxyCfg.enable {
        envVars = {
          http_proxy = proxyCfg.usedProxyAddress;
          https_proxy = proxyCfg.usedProxyAddress;
          all_proxy = proxyCfg.usedProxyAddress;
          no_proxy = lib.concatStringsSep "," proxyCfg.exceptions;
        };
      });
  };
}
