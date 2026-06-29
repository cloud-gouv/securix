# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
let
  cfg = config.securix.browser;
  inherit (lib)
    mkIf
    mkEnableOption
    types
    mkOption
    ;
  inherit (import ./option-types.nix { inherit lib; }) lockFlagEnum bookmarkType;

  homepage = if cfg.enableLocalHomepage then "http://127.0.0.1:8082" else cfg.homepage;
in
{
  options.securix.browser = {
    enable = mkEnableOption "browser preconfiguration";
    enableLocalHomepage = mkEnableOption "the local dynamic homepage";
    enableEncryptedMediaExtensions = mkEnableOption ''
      allow encrypted media extensions tobe used.

            This is required for websites like Netflix or YouTube.
    '';

    lockFlags = mkOption {
      type = types.listOf lockFlagEnum;
      description = ''
        The lock flags determine how locked down the browser configuration is.

        By default, we do not let the user install any extension, but we still
        let them modify the defaults.
      '';
    };

    homepage = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        URL to the home page.
        The home page is usually locked by default.
      '';
    };

    browsers = mkOption {
      type = types.listOf (
        types.enum [
          "firefox"
          "chromium"
        ]
      );
      # This is the default recommended one.
      default = [ "chromium" ];
    };

    extensions = mkOption {
      type = types.attrsOf (types.either types.attrs types.list);
      description = ''
        Per-browser attribute set of list of extensions to install in each instance.
      '';
    };

    bookmarks = mkOption {
      type = types.attrsOf (types.attrsOf (types.submodule bookmarkType));
      example = ''
        {
          Productivity = {
            Github = {
              href = "https://github.com";
              icon = "github.png";
            };
          };

          Entertainment = {
            Youtube = {
              href = "https://youtube.com";
              icon = "si-youtube";
            };
          };
        }
      '';
      description = ''
        Folders of bookmarks with their icons and link target.
      '';
    };
  };

  imports = [
    ./firefox.nix
    ./chromium.nix
    ./homepage-dashboard.nix
  ];

  config = mkIf cfg.enable {
    securix.browser = {
      # NOTE: this is a backward compatibility default.
      enableLocalHomepage = lib.mkDefault (lib.elem "firefox" cfg.browsers);
      extensions = {
        firefox = lib.mkDefault { ublock-origin = "uBlock0@raymondhill.net"; };
        chromium = lib.mkDefault [
          "ddkjiahejlhfcafbddmgiahcphecmpfh" # uBlock Origin Lite
        ];
      };

      lockFlags = lib.mkDefault [
        "allow-user-messaging-overrides"
        "allow-default-overrides"
      ];
    };

    securix.homepage-dashboard = {
      enable = cfg.enableLocalHomepage;
      inherit (cfg) bookmarks;
    };

    securix.firefox = {
      enable = lib.elem "firefox" cfg.browsers;
      inherit (cfg) enableEncryptedMediaExtensions;
      extensions = cfg.extensions.firefox or [ ];
      inherit (cfg) bookmarks lockFlags;
      inherit homepage;
    };

    securix.chromium = {
      enable = lib.elem "chromium" cfg.browsers;
      inherit (cfg) enableEncryptedMediaExtensions;
      extensions = cfg.extensions.chromium or { };
      inherit (cfg) bookmarks lockFlags;
      inherit homepage;
    };
  };
}
