# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.securix.graphical-interface;
in
{
  options.securix.graphical-interface.kde = {
    lookAndFeelPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "List of extra Look & Feel packages";
    };

    defaultLookAndFeel = mkOption {
      type = types.str;
      default = null;
      description = "Default look & feel package";
      example = "fr.dinum.bureautix";
    };
  };
  config = mkIf (cfg.variant == "kde") {
    services.xserver.enable = true;
    services.displayManager.sddm.enable = true;
    services.desktopManager.plasma6.enable = true;

    environment.systemPackages = cfg.kde.lookAndFeelPackages;
    environment.etc."xdg/kdeglobals".text = ''
      [KDE]
      LookAndFeelPackage=${cfg.kde.defaultLookAndFeel}
    '';
  };
}
