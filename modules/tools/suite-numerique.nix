# SPDX-FileCopyrightText: 2026 Pauline Legrand <pauline.legrand@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    optionals
    optionalAttrs
    listToAttrs
    ;
  cfg = config.securix.suite-numerique;

  apps = [
    {
      id = "tchap";
      name = "Tchap";
      url = "https://www.tchap.gouv.fr/";
      description = "Messagerie instantanée sécurisée de l'État";
    }
    {
      id = "docs";
      name = "Docs";
      url = "https://docs.numerique.gouv.fr/";
      description = "Éditeur de texte collaboratif";
    }
    {
      id = "visio";
      name = "Visio";
      url = "https://visio.numerique.gouv.fr/";
      description = "Visioconférence sécurisée de l'État";
    }
    {
      id = "fichiers";
      name = "Fichiers";
      url = "https://fichiers.numerique.gouv.fr/";
      description = "Stockage et partage de fichiers (bêta)";
    }
    {
      id = "grist";
      name = "Grist";
      url = "https://grist.numerique.gouv.fr/";
      description = "Tableur collaboratif (bêta)";
    }
    {
      id = "france-transfert";
      name = "France Transfert";
      url = "https://francetransfert.numerique.gouv.fr/upload";
      description = "Transfert de fichiers volumineux";
    }
    {
      id = "resana";
      name = "Resana";
      url = "https://resana.numerique.gouv.fr/public/";
      description = "Plateforme collaborative interministérielle";
    }
    {
      id = "rdv";
      name = "RDV Service Public";
      url = "https://rdv.anct.gouv.fr/";
      description = "Prise de rendez-vous en ligne";
    }
    {
      id = "demarche";
      name = "Démarche";
      url = "https://demarche.numerique.gouv.fr/";
      description = "Dématérialisation des démarches administratives";
    }
  ];

  iconsDir = ./suite-numerique-icons;


  makeDesktopItem =
    app:
    pkgs.makeDesktopItem {
      name = "lasuite-${app.id}";
      desktopName = app.name;
      comment = app.description;
      exec = "${lib.getExe pkgs.chromium} --app=${app.url} --class=lasuite-${app.id}";
      icon = "${iconsDir}/lasuite-${app.id}.svg";
      categories = [ "Network" ];
      startupWMClass = "lasuite-${app.id}";
    };

  desktopItems = map makeDesktopItem apps;

in
{
  options.securix.suite-numerique = {
    enable = mkEnableOption ''
      Raccourcis vers les services de LaSuite, la suite numérique de l'État
      (Tchap, Docs, Visio, Fichiers, Grist, France Transfert, Resana, RDV Service Public, Démarche).

      Les raccourcis .desktop permettent de lancer chaque service depuis le bureau KDE
      ou le menu des applications, dans Chromium en mode application.

      Les bookmarks Firefox sont ajoutés dans la barre de favoris via le module
      `securix.firefox`.
    '';

    addFirefoxBookmarks = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Ajouter les services de LaSuite dans la barre de favoris Firefox,
        via le module `securix.firefox.bookmarks`.
      '';
    };

    addDesktopShortcuts = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Ajouter les raccourcis .desktop pour chaque service de LaSuite.
        Ces raccourcis apparaissent dans le menu des applications KDE et peuvent
        être épinglés sur le bureau ou dans la barre des tâches.
      '';
    };
  };

  environment.etc."chromium/policies/recommended/lasuite.json".text = builtins.toJSON {
    BookmarkBarEnabled = true;
    ManagedBookmarks = map (app: {
      name = app.name;
      url = app.url;
    }) apps;
  };

  config = mkIf cfg.enable {
    environment.systemPackages = optionals cfg.addDesktopShortcuts desktopItems;

    securix.firefox.bookmarks = optionalAttrs cfg.addFirefoxBookmarks {
      "LaSuite" = listToAttrs (
        map (app: {
          name = app.name;
          value = {
            href = app.url;
            description = app.description;
          };
        }) apps
      );
    };
  };
}
