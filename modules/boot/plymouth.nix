# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.securix.boot.plymouth;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.securix.boot.plymouth = {
    enable = mkEnableOption "plymouth boot screen";
    logo = mkOption {
      type = types.path;
      default = "${pkgs.nixos-icons}/share/icons/hicolor/128x128/apps/nix-snowflake.png";
      description = "Logo for Plymouth";
    };
  };

  config = mkIf cfg.enable {
    boot = {
      consoleLogLevel = lib.mkDefault 3;
      initrd.verbose = false;
      initrd.systemd.enable = true;
      kernelParams = [
        "quiet"
        "splash"
        "udev.log_priority=3"
        "rd.systemd.show_status=auto"
      ];

      plymouth = {
        enable = true;
        font = "${pkgs.hack-font}/share/fonts/truetype/Hack-Regular.ttf";
        inherit (cfg) logo;
      };
    };
  };
}
