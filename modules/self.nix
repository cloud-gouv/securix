# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  vpnProfiles,
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.securix.self;
  inherit (lib)
    mkOption
    types
    optional
    elemAt
    splitString
    substring
    mkDefault
    ;
  deriveUsernameFromEmail =
    email:
    let
      parts = splitString "." email;
      firstName = elemAt 0 parts;
      lastName = elemAt 1 parts;
      firstLetter = substring 0 1 firstName;
      usernameLimit = 32;
    in
    substring 0 usernameLimit "${firstLetter}${lastName}";
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

    email = mkOption {
      type = types.str;
      description = "Adresse email de l'agent";
    };

    username = mkOption {
      type = types.str;
      default = deriveUsernameFromEmail cfg.email;
      defaultText = ''<première lettre de prénom><nom de famille> tronqué à 32 caractères'';
      description = ''
        Nom d'utilisateur de la session PAM, dérivé par l'email en calculant:

        <première lettre de l'email><nom de famille>

        Tronqué à 32 caractères, limite de PAM.
      '';
      example = "rlahfa";
    };

    inventoryId = mkOption {
      type = types.int;
      description = "Numéro d'inventaire du système";
      example = 123456;
    };

    hardwareSKU = mkOption {
      type = types.enum [ "x280" "hp645G11" "latitude5340" ];
      description = "Identifiant de configuration du matériel";
      example = "x280";
    };

    developer = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Mode développeur pour cet opérateur.

        Le mode développeur permet de développer l'OS sécurisé sans les bridages.
        Il n'est pas conçu pour *développer* d'autres choses en meme temps.

        ATTENTION: Le mode développeur N'EST PAS CONFORME aux règles de sécurité
        de l'ANSSI en matière de poste d'administration. Celui-ci doit etre utilisé
        avec parcimonie.
      '';
    };

    hashedPassword = mkOption {
      type = types.str;
      description = "Mot de passe hachée en ycrypt pour la session utilisateur.";
    };

    defaultLoginShell = mkOption {
      type = types.package;
      default = pkgs.bashInteractive;
      description = "Shell par défaut de connexion pour la session utilisateur.";
    };

    identifier = mkOption {
      type = types.str;
      internal = true;
      description = "Identifiant de customization de la machine";
      example = "ryan_lahfa";
    };

    bit = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "Octet pour l'adresse IPv4 publique dans le VPN";
      example = 1;
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

    allowedVPNs = mkOption {
      type = types.listOf (types.enum (builtins.attrNames vpnProfiles));
      default = [ ];
      description = "Liste des VPNs provisionnés pour l'utilisateur";
      example = [ "vpn-01" ];
    };

    teams = mkOption {
      type = types.listOf types.str;
      description = "Liste des équipes dans lequel l'utilisateur est";
      example = [
        "product-01"
        "product-02"
        "financial-dpt"
        "security-team"
      ];
    };
  };

  config = {
    warnings = optional cfg.developer ''
      Le mode développeur est activé pour ${cfg.email}, cette image n'est pas conforme aux règles de l'ANSSI.
    '';

    services.getty.helpLine = ''
      Bienvenue sur Sécurix (identifiant ${toString cfg.inventoryId}), utilisateur principal: ${toString cfg.email}.
    '';

    networking.hostName = mkDefault "securix-${cfg.edition}-${toString cfg.inventoryId}";
    users.users.${cfg.username}.shell = cfg.defaultLoginShell;
  };
}
