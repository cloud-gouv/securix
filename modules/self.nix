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
    mkMerge
    mkIf
    optionalString
    mkRenamedOptionModule
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

  isUserConfig = cfg.selfDescriptionType == "user" || cfg.selfDescriptionType == "both";
  isMachineConfig = cfg.selfDescriptionType == "machine" || cfg.selfDescriptionType == "both";
  machineIdentifier =
    if cfg.machine.inventoryId != null then
      cfg.machine.inventoryId
    else if cfg.machine.serialNumber != null then
      cfg.machine.serialNumber
    else
      "unknown machine";
in
{
  options.securix.self = {
    selfDescriptionType = mkOption {
      type = types.enum [
        "user"
        "machine"
        "both"
      ];
      # Backward compatibility with original Securix systems.
      default = "both";
      example = "user";
    };

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

    user = {
      email = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Adresse email de l'agent";
      };

      username = mkOption {
        type = types.nullOr types.str;
        default = if cfg.email != null then deriveUsernameFromEmail cfg.email else null;
        defaultText = ''<première lettre de prénom><nom de famille> tronqué à 32 caractères'';
        description = ''
          Nom d'utilisateur de la session PAM, dérivé par l'email en calculant:

          <première lettre de l'email><nom de famille>

          Tronqué à 32 caractères, limite de PAM.
        '';
        example = "rlahfa";
      };

      hashedPassword = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Mot de passe hachée en ycrypt pour la session utilisateur.";
      };

      u2f_keys = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Liste de clefs U2F générés par `pamu2cfg`
          NOTE: Il faut passer les bons paramètres appid et origin à pamu2cfg si on veut que la clef soit reconnue.
          Ces paramètres sont documentés dans `config.securix.pam.u2f`.
        '';
      };

      defaultLoginShell = mkOption {
        type = types.package;
        default = pkgs.bashInteractive;
        description = "Shell par défaut de connexion pour la session utilisateur.";
      };

      bit = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Octet pour l'adresse IPv4 publique dans le VPN";
        example = 1;
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
        default = [ ];
        example = [
          "product-01"
          "product-02"
          "financial-dpt"
          "security-team"
        ];
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
    };

    machine = {
      serialNumber = mkOption {
        type = types.nullOr types.str;
        description = "Numéro de série du système";
        example = "XYZZZZZZ";
      };

      inventoryId = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Numéro d'inventaire du système";
        example = 123456;
      };

      hardwareSKU = mkOption {
        type = types.enum [
          "x280"
          "elitebook645g11"
          "latitude5340"
          "t14g6"
          "x9-15"
          "e14-g7"
        ];
        description = "Identifiant de configuration du matériel";
        example = "x280";
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

      users = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          List of assigned usernames to this machine.
          Such a username must exist in the inventory of users and is identified by its filename without the extension.
        '';
        example = [ "rlahfa" ];
      };

      # Legacy attribute only for original Securix systems.
      identifier = mkOption {
        type = types.str;
        internal = true;
        description = "Identifiant de customization de la machine";
        example = "ryan_lahfa";
      };
    };
  };

  imports = [
    # User part migration
    (mkRenamedOptionModule [ "securix" "self" "email" ] [ "securix" "self" "user" "email" ])
    (mkRenamedOptionModule [ "securix" "self" "username" ] [ "securix" "self" "user" "username" ])
    (mkRenamedOptionModule
      [ "securix" "self" "hashedPassword" ]
      [ "securix" "self" "user" "hashedPassword" ]
    )
    (mkRenamedOptionModule
      [ "securix" "self" "defaultLoginShell" ]
      [ "securix" "self" "user" "defaultLoginShell" ]
    )
    (mkRenamedOptionModule [ "securix" "self" "bit" ] [ "securix" "self" "user" "bit" ])
    (mkRenamedOptionModule [ "securix" "self" "allowedVPNs" ] [ "securix" "self" "user" "allowedVPNs" ])
    (mkRenamedOptionModule [ "securix" "self" "teams" ] [ "securix" "self" "user" "teams" ])
    (mkRenamedOptionModule [ "securix" "self" "developer" ] [ "securix" "self" "user" "developer" ])

    # Machine part migration
    (mkRenamedOptionModule
      [ "securix" "self" "inventoryId" ]
      [ "securix" "self" "machine" "inventoryId" ]
    )
    (mkRenamedOptionModule
      [ "securix" "self" "hardwareSKU" ]
      [ "securix" "self" "machine" "hardwareSKU" ]
    )
    (mkRenamedOptionModule
      [ "securix" "self" "infraRepositoryPath" ]
      [ "securix" "self" "machine" "infraRepositoryPath" ]
    )
    (mkRenamedOptionModule
      [ "securix" "self" "infraRepositorySubdir" ]
      [ "securix" "self" "machine" "infraRepositorySubdir" ]
    )
    (mkRenamedOptionModule
      [ "securix" "self" "identifier" ]
      [ "securix" "self" "machine" "identifier" ]
    )
  ];

  config = mkMerge [
    {
      warnings = optional (isUserConfig && cfg.user.developer) ''
        Le mode développeur est activé pour ${cfg.user.email}, cette image n'est pas conforme aux règles de l'ANSSI.
      '';
      services.getty.helpLine = optionalString isMachineConfig ''
        Bienvenue sur Sécurix (identifiant ${toString machineIdentifier}).
        ${optionalString isUserConfig "Utilisateur principal: ${toString cfg.user.email}."}
      '';
      networking.hostName = mkDefault "securix-${cfg.edition}-${toString machineIdentifier}";
    }
    (mkIf isUserConfig {
      warnings = optional cfg.user.developer ''
        Le mode développeur est activé pour ${cfg.user.email}, cette image n'est pas conforme aux règles de l'ANSSI.
      '';
      users.users.${cfg.user.username}.shell = cfg.user.defaultLoginShell;
      securix.pam.u2f.keys.${cfg.user.username} = cfg.user.u2f_keys;
    })
  ];
}
