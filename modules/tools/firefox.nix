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
  inherit (lib) listToAttrs mkOption mkEnableOption;
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

  # Active `privacy.resistFingerprinting` + letterboxing. Normalise
  # plusieurs vecteurs de fingerprinting (timezone, taille d'écran,
  # canvas, audio, liste de polices), mais CASSE certains sites —
  # notamment ceux qui vérifient une cohérence entre la taille
  # d'écran annoncée et la vraie, ou les portails intranet qui
  # dépendent du timezone local. Opt-in par déploiement ; désactivé
  # par défaut pour préserver la compatibilité avec les portails
  # gouvernementaux. Voir `docs/manual/src/user/browser-hardening.md`.
  options.securix.firefox.hardenFingerprinting = mkEnableOption "Firefox fingerprinting resistance (privacy.resistFingerprinting + letterboxing)";

  config = {
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

    programs.firefox = {
      enable = true;
      # Pin to Firefox ESR (security-only update channel, Mozilla-supported).
      # Rationale: admin workstation posture favours a predictable release
      # cadence with security-only patches over the rolling branch's feature
      # churn. Upstream ESR ships ~1 major/year with ~1 year overlap; see
      # `docs/manual/src/user/browser-baseline.md` for the update policy.
      package = pkgs.firefox-esr;
      languagePacks = [
        "fr"
        "en-US"
      ];

      nativeMessagingHosts.packages = [ pkgs.tridactyl-native ];

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
        NewTabPage = false;

        # Don't save password on Firefox to avoid data losses
        PasswordManagerEnabled = false;
        OfferToSaveLogins = false;

        # Unnecessary.
        DontCheckDefaultBrowser = true;
        # Firefox version is managed by Sécurix
        AppAutoUpdate = false;
        DisableAppUpdate = true;

        # You are not supposed to watch Netflix on Sécurix.
        EncryptedMediaExtensions = {
          Enabled = lib.mkDefault false;
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
            # Block all manual extension install. You NEED to propose your extension to the Sécurix repository.
            "*".installation_mode = "blocked";
          }
          // (listToAttrs [
            (extension "ublock-origin" "uBlock0@raymondhill.net")
            (extension "bitwarden-password-manager" "{446900e4-71c2-419f-a6a7-df9c091e268b}")
          ]);

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
          Locked = false;
        };

        # ───────────────────────────────────────────────────────────────
        # Durcissement browser — voir `docs/manual/src/user/browser-hardening.md`
        # pour l'analyse détaillée (surface WebRTC, CVE, matrice de couverture
        # et implications admin / RSSI).
        # ───────────────────────────────────────────────────────────────

        # Permissions par défaut verrouillées côté policy.
        # La caméra et le micro ne sont PAS auto-accordés (pas de liste
        # Allow) : chaque site qui demande voit le prompt Firefox natif,
        # l'utilisateur décide par session. `persistDecisions=false` ci-dessous
        # empêche la persistance (« Se souvenir de cette décision »).
        Permissions = {
          Camera = {
            Locked = true;
          };
          Microphone = {
            Locked = true;
          };
          Location = {
            BlockNewRequests = true;
            Locked = true;
          };
          Notifications = {
            BlockNewRequests = true;
            Locked = true;
          };
          Autoplay = {
            Default = "block-audio-video";
            Locked = true;
          };
        };

        # Moteur de recherche par défaut : Qwant (opéré en France,
        # infrastructure UE, politique no-tracking déclarée, aligné
        # avec le principe de souveraineté numérique gouvernementale).
        # `Add` ajoute l'entrée Qwant explicitement, au cas où le pack
        # de langue FR ne serait pas actif à l'install (edge case :
        # système en locale en-US). Non verrouillé (pas de `Locked`) :
        # l'utilisateur peut basculer sur DuckDuckGo, Google, Startpage
        # selon ses besoins opérationnels. Voir browser-hardening.md §4.8.
        SearchEngines = {
          Default = "Qwant";
          Add = [
            {
              Name = "Qwant";
              URLTemplate = "https://www.qwant.com/?q={searchTerms}";
              Method = "GET";
              IconURL = "https://www.qwant.com/favicon.ico";
              Alias = "qw";
              Description = "Moteur de recherche souverain français (infrastructure UE, politique no-tracking).";
            }
          ];
        };

        # Préférences durcies via les clés about:config.
        # Chaque valeur est `Status = "locked"` — l'utilisateur ne peut
        # pas la réactiver via about:config. Chaque groupe renvoie au
        # point correspondant de la matrice de couverture dans
        # browser-hardening.md.
        Preferences = {
          # === WebRTC — Couche A (prefs globales) ===
          # API activée : nécessaire pour les outils visio (Jitsi, BBB,
          # Teams-web, …). Le durcissement restreint la surface, pas
          # l'accès à la fonctionnalité.
          "media.peerconnection.enabled" = {
            Value = true;
            Status = "locked";
          };
          # Pas de host candidate → zéro fuite IP LAN / VPN aux STUN.
          "media.peerconnection.ice.no_host" = {
            Value = true;
            Status = "locked";
          };
          # Une seule interface sortante → pas d'énumération multi-NIC.
          "media.peerconnection.ice.default_address_only" = {
            Value = true;
            Status = "locked";
          };
          # Force TURN si un proxy système est configuré (audit réseau).
          "media.peerconnection.ice.proxy_only_if_behind_proxy" = {
            Value = true;
            Status = "locked";
          };
          # Peer identity : feature WebRTC legacy, surface code inutile.
          "media.peerconnection.identity.enabled" = {
            Value = false;
            Status = "locked";
          };
          # enumerateDevices nécessaire pour négocier caméra / micro
          # dans Jitsi — reste activé.
          "media.navigator.enabled" = {
            Value = true;
            Status = "locked";
          };
          # TURN nécessaire pour NAT symétrique en mobilité.
          "media.peerconnection.turn.disable" = {
            Value = false;
            Status = "locked";
          };

          # === Permissions — Couche B (prompt systématique) ===
          # 0 = ask ; 1 = allow silently ; 2 = block silently.
          "permissions.default.camera" = {
            Value = 0;
            Status = "locked";
          };
          "permissions.default.microphone" = {
            Value = 0;
            Status = "locked";
          };
          "permissions.default.screen" = {
            Value = 0;
            Status = "locked";
          };
          "permissions.default.geo" = {
            Value = 2;
            Status = "locked";
          };
          # Pas de « Se souvenir de cette décision » : la permission
          # retombe à `ask` à la fermeture de l'onglet.
          "privacy.permissionPrompts.persistDecisions" = {
            Value = false;
            Status = "locked";
          };

          # === DoH (TRR) désactivé — conserve le DNS entreprise ===
          "network.trr.mode" = {
            Value = 5;
            Status = "locked";
          };
          "network.trr.uri" = {
            Value = "";
            Status = "locked";
          };

          # === PPA — Privacy-Preserving Attribution ===
          # Activé par défaut depuis Firefox 128 (juillet 2024).
          "dom.private-attribution.submission.enabled" = {
            Value = false;
            Status = "locked";
          };

          # === Safe Browsing désactivé — pas de ping Mozilla / Google ===
          "browser.safebrowsing.malware.enabled" = {
            Value = false;
            Status = "locked";
          };
          "browser.safebrowsing.phishing.enabled" = {
            Value = false;
            Status = "locked";
          };
          "browser.safebrowsing.downloads.enabled" = {
            Value = false;
            Status = "locked";
          };
          "browser.safebrowsing.downloads.remote.enabled" = {
            Value = false;
            Status = "locked";
          };

          # === Autoplay — redondance avec Permissions.Autoplay (belt + braces) ===
          "media.autoplay.default" = {
            Value = 5;
            Status = "locked";
          };
          "media.autoplay.blocking_policy" = {
            Value = 2;
            Status = "locked";
          };

          # === Géolocalisation — pas de requête Google Location Services ===
          "geo.enabled" = {
            Value = false;
            Status = "locked";
          };
          "geo.provider.use_geoclue" = {
            Value = false;
            Status = "locked";
          };

          # === Connexions spéculatives / DNS prefetch ===
          # Élimine les fuites DNS passives et les handshakes
          # pre-navigation vers les domaines survolés.
          "network.prefetch-next" = {
            Value = false;
            Status = "locked";
          };
          "network.dns.disablePrefetch" = {
            Value = true;
            Status = "locked";
          };
          "network.predictor.enabled" = {
            Value = false;
            Status = "locked";
          };
          "network.http.speculative-parallel-limit" = {
            Value = 0;
            Status = "locked";
          };

          # === Suggestions de recherche (requête moteur à chaque frappe) ===
          "browser.search.suggest.enabled" = {
            Value = false;
            Status = "locked";
          };
          "browser.urlbar.suggest.searches" = {
            Value = false;
            Status = "locked";
          };

          # === Debug distant ===
          # Le debugger local reste disponible (utile pour les admins) ;
          # seul le remote debugging TCP est désactivé.
          "devtools.debugger.remote-enabled" = {
            Value = false;
            Status = "locked";
          };

          # === New Tab — pas de contenu sponsorisé ===
          "browser.newtabpage.activity-stream.showSponsored" = {
            Value = false;
            Status = "locked";
          };
          "browser.newtabpage.activity-stream.showSponsoredTopSites" = {
            Value = false;
            Status = "locked";
          };

          # === Capture automatique de formulaires (saisie mots de passe) ===
          # PasswordManagerEnabled=false couvre le stockage ; cette pref
          # ferme la collecte passive via formless capture.
          "signon.formlessCapture.enabled" = {
            Value = false;
            Status = "locked";
          };
        }
        // lib.optionalAttrs cfg.hardenFingerprinting {
          # === Résistance au fingerprinting (opt-in) ===
          # Casse des sites qui vérifient une cohérence timezone /
          # taille d'écran / canvas. À n'activer que si le parc visé
          # n'a pas besoin d'accéder à des portails sensibles à cela.
          "privacy.resistFingerprinting" = {
            Value = true;
            Status = "locked";
          };
          "privacy.resistFingerprinting.letterboxing" = {
            Value = true;
            Status = "locked";
          };
        };
      };

      # Let the user override the default.
      preferencesStatus = "default";
    };
  };
}
