# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, lib, pkgs, ... }:
let
  cfg = config.securix.graphical-interface;
  inherit (lib) mkIf;
in
{
  config = mkIf cfg.enable {
    fonts = {
      packages = with pkgs; [
        hermit
        source-code-pro
        terminus_font
        font-awesome
        font-awesome_4
        dejavu_fonts
        hack-font
        noto-fonts
        cantarell-fonts
        powerline-fonts
        roboto
        roboto-slab
        eb-garamond
        liberation_ttf
        fira-code
        fira-code-symbols
        mplus-outline-fonts.githubRelease
        dina-font
        proggyfonts
      ];
      fontconfig = {
        enable = true;
        defaultFonts = {
          monospace = ["Source Code Pro for Powerline" "Roboto Mono for Powerline"];
          sansSerif = ["Roboto"];
          serif = ["Roboto Slab"];
        };
      };
    };
  };
}
