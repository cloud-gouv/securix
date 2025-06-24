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
        # Remove this patch once https://nixpk.gs/pr-tracker.html?pr=419585 lands in a channel of our nixpkgs.
        package = pkgs.lix.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ ./patches/LIX_2_91_CVE-2025-46415_46416.patch ];
        });
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
