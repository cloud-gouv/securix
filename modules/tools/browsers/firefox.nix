# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
let
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    mapAttrs'
    ;
  inherit (lib.types)
    attrsOf
    enum
    submodule
    str
    nullOr
    ;
  inherit (import ./option-types.nix { inherit lib; }) lockFlagEnum bookmarkType proxyConfig;

  cfg = config.securix.firefox;
in
{
  options.securix.firefox = {
    enable = mkEnableOption "Firefox pre-configuration";
    enableEncryptedMediaExtensions = mkEnableOption ''
      allow encrypted media extensions to be used.
            This is required for websites like Netflix or YouTube.
    '';

    lockFlags = mkOption {
      type = enum lockFlagEnum;
      default = [
        "allow-default-overrides"
        "allow-user-messaging-overrides"
      ];

      description = ''
        The lock flags determine how locked down the Firefox configuration is.

        By default, we do not let the user install any extension, but we still
        let them modify the Firefox defaults.
      '';
    };

    proxy = mkOption {
      type = nullOr submodule proxyConfig;
      default = null;
      description = ''
        Proxy configuration for this instance of Firefox.
        By default, it configures nothing.
      '';
    };

    extensions = mkOption {
      type = attrsOf str;
      default = { };
      description = ''
        Attribute set of extensions to install to the Firefox instance.

        The key should be the short ID of the extension in the Mozilla store.
        The value should be the UUID.
      '';
      example = {
        bitwarden-password-manager = "{446900e4-71c2-419f-a6a7-df9c091e268b}";
      };
    };

    bookmarks = mkOption {
      type = attrsOf (attrsOf (submodule bookmarkType));
      default = { };
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
        Bookmarks to show to homepage and firefox bookmarks.
      '';
    };
  };

  config = mkIf cfg.enable {
    programs.firefox = {
      enable = true;
      languagePacks = [
        "fr"
        "en-US"
      ];

      policies = {
        Homepage = {
          URL = cfg.homepage;
          # By default, the user is not allowed to update the homepage.
          # This can be bypassed if the lock flag contains an allow element.
          Locked = !lib.elem "allow-homepage-overrides" cfg.lockFlags;
          # homepage-locked will prevent the user from restoring session, that's bad UX!
          StartPage = "homepage";
        };

        Bookmarks = lib.flatten (
          map (
            folder:
            map (
              { name, value }:
              {
                Title = name;
                URL = value.href;
                Folder = folder.name;
              }
            ) (lib.attrsToList folder.value)
          ) (lib.attrsToList cfg.bookmarks)
        );

        DisplayBookmarksToolbar = "always";
        DisableProfileImport = true;
        NoDefaultBookmarks = true;
        NewTabPage = false;

        # Don't save password on Firefox to avoid data losses
        PasswordManagerEnabled = false;
        OfferToSaveLogins = false;

        # Unnecessary.
        DontCheckDefaultBrowser = true;
        # Firefox version is managed by Sécurix
        AppAutoUpdate = false;
        DisableAppUpdate = true;

        # By default, we disable DRMs APIs which makes little sense
        # on an admin laptop. Office laptops might want to re-enable this.
        EncryptedMediaExtensions = {
          Enabled = lib.mkDefault cfg.enableEncryptedMediaExtensions;
        };

        Proxy = mkIf (cfg.proxy != null) {
          Mode =
            if cfg.proxy.httpProxy != null then
              "manual"
            else if cfg.proxy.autoConfigURL != null then
              "autoConfig"
            else
              "autoDetect";

          Locked = cfg.proxy.locked;

          HTTPProxy = mkIf (cfg.proxy.httpProxy != null) cfg.proxy.httpProxy;
          UseHTTPProxyForAllProtocols = mkIf (cfg.proxy.httpProxy != null) true;
          SOCKSVersion = 5;

          Passthrough = cfg.proxy.noProxy;
          AutoConfigURL = mkIf (cfg.proxy.autoConfigURL != null) cfg.proxy.autoConfigURL;

          AutoLogin = lib.mkDefault true;
          UseProxyForDNS = lib.mkDefault true;
        };

        ExtensionSettings =
          let
            extension = shortId: uuid: {
              name = uuid;
              value = {
                install_url = "https://addons.mozilla.org/en-US/firefox/downloads/latest/${shortId}/latest.xpi";
                installation_mode = "normal_installed";
              };
            };
          in
          {
            # By default, we will block any extension installs.
            # This is what makes the most sense on an admin laptop
            # and any IT operated asset.
            # In certain cases, the browser could be unlocked to simplify operations
            # e.g. you use your own extension store.
            "*".installation_mode =
              if lib.elem "allow-extension-installs" cfg.lockFlags then "allowed" else "blocked";
          }
          // mapAttrs' extension cfg.extensions;
        # // (listToAttrs [
        #   (extension "bitwarden-password-manager" "{446900e4-71c2-419f-a6a7-df9c091e268b}")
        # ]);

        DisablePocket = true;
        DisableFirefoxAccounts = true;
        DisableTelemetry = true;
        DisableFirefoxStudies = true;

        UserMessaging = {
          ExtensionRecommendations = false;
          UrlbarInterventions = false;
          MoreFromMozilla = false;
          FirefoxLabs = false;
          # If people wants to get spammed by Firefox… They can.
          # We may want to lock down user messaging for some hardening reason.
          Locked = !lib.elem "allow-user-messaging-overrides" cfg.lockFlags;
        };
      };

      # By default, we would allow the user to override the preferences.
      # In certain cases, we may want to lock further down this.
      preferencesStatus =
        if lib.elem "allow-default-overrides" cfg.lockFlags then "default" else "locked";
    };
  };
}
