# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
let
  inherit (lib) mkIf;
  cfg = config.securix.graphical-interface;
in
{
  config = mkIf (cfg.variant == "cinnamon") {
    services.xserver = {
      enable = true;
      displayManager = {
        defaultSession = "cinnamon";
        lightdm.enable = true;
      };
      desktopManager.cinnamon.enable = true;

    };
  };
}
