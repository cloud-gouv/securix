# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ pkgs, config, lib, ... }:
let
  inherit (lib) mkIf;
  cfg = config.securix.graphical-interface;
in
{
  imports = [
    ./sway-config.nix
  ];

  config = mkIf (cfg.variant == "sway") {
    environment.systemPackages = with pkgs; [
      grim # screenshot functionality
      slurp # screenshot functionality
      wl-clipboard # wl-copy and wl-paste for copy/paste from stdin / stdout
      mako # notification system developed by swaywm maintainer
      swaylock # a locker
      wofi # a simple dmenu
      i3status-rust # a resource efficient status bar
      networkmanagerapplet # for nm-connection-editor
    ];

    programs.gnupg.agent.pinentryPackage = pkgs.pinentry-curses;
    programs.nm-applet.enable = true;

    # Enable the gnome-keyring secrets vault. 
    # Will be exposed through DBus to programs willing to store secrets.
    services.gnome.gnome-keyring.enable = true;

    # enable Sway window manager
    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };

    services.greetd = {                                                      
      enable = true;                                                         
      settings = {                                                           
        default_session = {                                                  
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd sway";
          user = "greeter";                                                  
        };                                                                   
      };                                                                     
    };
  };
}
