# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib) listToAttrs mkOption;
  inherit (lib.types) attrsOf submodule str;

  cfg = config.securix.firefox;

  bookmarkType = submodule {
    options = {
      icon = mkOption {
        type = str;
        default = "";
        description = ''
          Name of the icon of the bookmark.
        '';
      };

      href = mkOption {
        type = str;
        description = ''
          URL of the website that the bookmark points to.
        '';
      };

      description = mkOption {
        type = str;
        default = "";
        description = ''
          Description of the website that the bookmark points to.
        '';
      };
    };
  };
in
{
  options.securix.firefox.bookmarks = mkOption {
    type = attrsOf (attrsOf bookmarkType);
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

  config = {
    # This spawns the dashboard on 127.0.0.1:8082.
    services.homepage-dashboard = {
      enable = true;

      bookmarks = (
        map (
          { name, value }:
          {
            ${name} = (
              map (
                { name, value }:
                {
                  ${name} = [ value ];
                }
              ) (lib.attrsToList value)
            );
          }
        ) (lib.attrsToList cfg.bookmarks)
      );
      # TODO: add services and automatically ping all our seed-bastions & bastions for workers.

      # TODO: kubernetes, etc.
    };

    programs.firefox = {
      enable = true;
      languagePacks = [
        "fr"
        "en-US"
      ];

      nativeMessagingHosts.packages = [ (pkgs.tridactyl-native) ];

      policies = {
        Homepage = {
          # Connect to the local dashboard.
          URL = "http://127.0.0.1:8082";
          # The user cannot change the homepage. All changes should go via Sécurix.
          Locked = true;
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

        # Don't save password on Firefox to avoid data losses
        PasswordManagerEnabled = false;
        OfferToSaveLogins = false;

        # Unnecessary.
        DontCheckDefaultBrowser = true;

        # You are not supposed to watch Netflix on Sécurix.
        EncryptedMediaExtensions = {
          Enabled = false;
        };

        ExtensionsSettings =
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
            # Block all manual extension install. You NEED to propose your extension to the Sécurix repository.
            "*".installation_mode = "blocked";
          }
          // (listToAttrs [
            (extension "ublock-origin" "uBlock0@raymondhill.net")
            (extension "umatrix" "uMatrix@raymondhill.net")
            (extension "tree-style-tab" "treestyletab@piro.sakura.ne.jp")
            (extension "bitwarden-password-manager" "{446900e4-71c2-419f-a6a7-df9c091e268b}")
          ]);

        DisablePocket = true;
        DisableFirefoxAccounts = true;
        DisableTelemetry = true;

        UserMessaging = {
          ExtensionRecommendations = false;
          UrlbarInterventions = false;
          MoreFromMozilla = false;
          FirefoxLabs = false;
          # If people wants to get spammed by Firefox… They can.
          Locked = false;
        };
      };

      # Let the user override the default.
      preferencesStatus = "default";
    };
  };
}
