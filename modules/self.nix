# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
let
  cfg = config.securix.self;
  inherit (lib)
    mkOption
    types
    optional
    mkDefault
    ;
in
{
  options.securix.self = {
    mainDisk = mkOption {
      type = types.str;
      description = "Disque du système";
      example = "/dev/nvme0n1";
    };

    edition = mkOption {
      type = types.str;
      description = "Édition du système Sécurix";
      example = "acme-corp";
    };

    defaultOperator = mkOption {
      type = types.nullOr types.str;
      description = ''
        Utilisateur par défaut du poste.

        Si aucun utilisateur par défaut n'est renseigné, le poste peut être utilisé par tous les opérateurs de l'équipe.
      '';
    };

    inventoryId = mkOption {
      type = types.int;
      description = "Numéro d'inventaire du système";
      example = 123456;
    };

    hardwareSKU = mkOption {
      type = types.enum [ "x280" ];
      description = "Identifiant de configuration du matériel";
      example = "x280";
    };

    developer = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Mode développeur pour ce poste.

        Le mode développeur permet de développer l'OS sécurisé sans les bridages.
        Il n'est pas conçu pour *développer* d'autres choses en meme temps.

        ATTENTION: Le mode développeur N'EST PAS CONFORME aux règles de sécurité
        de l'ANSSI en matière de poste d'administration. Celui-ci doit etre utilisé
        avec parcimonie.
      '';
    };

    identifier = mkOption {
      type = types.str;
      internal = true;
      description = "Identifiant de customization de la machine";
      example = "ryan_lahfa";
    };

    infraRepositoryPath = mkOption {
      type = types.path;
      default = "/etc/infrastructure";
      description = "Chemin vers le référentiel d'infrastructure";
    };

    infraRepositorySubdir = mkOption {
      type = types.str;
      default = "securix";
      description = "Chemin vers la souche Sécurix utilisé dans le référentiel d'infrastructure";
      example = "securix-security-team";
    };

    team = mkOption {
      type = types.str;
      description = "Équipe dans lequel la machine est utilisée";
      example = "security-team";
    };
  };

  config = {
    warnings = optional cfg.developer ''
      Le mode développeur est activé pour la machine ${cfg.identifier}, cette image n'est pas conforme aux règles de l'ANSSI.
    '';

    networking.hostName = mkDefault "securix-${cfg.edition}-${toString cfg.inventoryId}";
  };
}
