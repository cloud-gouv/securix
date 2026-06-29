# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
let
  cfg = config.securix.homepage-dashboard;
  inherit (lib) mkIf mkOption mkEnableOption;
in
{
  config = mkIf cfg.enable {
    # This spawns the dashboard on 127.0.0.1:8082.
    services.homepage-dashboard = {
      enable = true;

      bookmarks = map (
        { name, value }:
        {
          ${name} = map (
            { name, value }:
            {
              ${name} = [ value ];
            }
          ) (lib.attrsToList value);
        }
      ) (lib.attrsToList cfg.bookmarks);
    };
  };
}
