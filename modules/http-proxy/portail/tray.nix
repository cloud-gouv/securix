# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.plasma-portail-tray-icon;
  inherit (lib) mkIf mkEnableOption mkPackageOption;
in
{
  options.programs.plasma-portail-tray-icon = {
    enable = mkEnableOption "Portail tray icon for Plasma";
    package = mkPackageOption pkgs "plasma-portail-tray-icon" { };
  };

  config = mkIf cfg.enable {
    systemd.user.services.portail-plasma-tray-icon = {
      wantedBy = [ "graphical-session.target" ];
      description = "Portail tray icon for Plasma";

      # Python `print` statements are buffered, so they won't print immediately unless you disable buffering or flush explicitly.
      environment.PYTHONUNBUFFERED = "1";
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/tray";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
