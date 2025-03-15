# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

# The list of authorized users to manipulate an admin laptop.
# Basically, the inventory.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.securix.users;
  self = config.securix.self;

  mkOperator =
    operator:
    let
      developerMode = operator.developer && self.developer or false;
    in
    {
      isNormalUser = true;
      inherit (operator) hashedPassword;
      extraGroups =
        # In developer mode, you are allowed to use `sudo`.
        optional developerMode "wheel" ++ [
          "networkmanager"
          "video" # webcam?
          "dialout" # console série
          "wireshark" # debuggage trames
          "tss" # tpm2
          "operator" # can upgrade the system permissionlessly
        ];
    };

  inherit (lib)
    mkEnableOption
    optional
    mapAttrs
    mkOption
    types
    filterAttrs
    elem
    ;

  userOpts = {
    options = {
      username = mkOption {
        type = types.str;
        example = "rlahfa";
        description = "Nom d'utilisateur de l'opérateur";
      };

      email = mkOption {
        type = types.str;
        description = "Addresse email de l'agent";
      };

      hashedPassword = mkOption {
        type = types.str;
        description = ''
          Mot de passe hachée en ycrypt pour la session utilisateur.

          Pour générer le mot de passe, utiliser: `mkpasswd -sm Ycrypt`
        '';
      };

      defaultLoginShell = mkOption {
        type = types.package;
        default = pkgs.bashInteractive;
        description = "Shell par défaut de connexion pour l'utilisateur.";
      };

      bit = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Octet pour l'adresse IPv4 publique dans le VPN";
        example = 1;
      };

      allowedVPNs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List des VPNs provisionnés pour l'utilisateur";
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

      developer = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Mode développeur pour cet opérateur.
          Pour être fonctionnel, le mode développeur doit aussi être activé pour ce poste.

          Le mode développeur permet de développer l'OS sécurisé sans les bridages.
          Il n'est pas conçu pour *développer* d'autres choses en meme temps.

          ATTENTION: Le mode développeur N'EST PAS CONFORME aux règles de sécurité
          de l'ANSSI en matière de poste d'administration. Celui-ci doit etre utilisé
          avec parcimonie.
        '';
      };
    };
  };
in
{
  options.securix.users = {
    allowAnyOperator = mkEnableOption "the possibility for any operator to log in on this machine.";

    users = mkOption {
      type = types.attrsOf (types.submodule userOpts);
      default = { };
      description = "Utilisateurs de Sécurix";
    };

    allowedUsers = mkOption {
      type = types.attrsOf (types.submodule userOpts);
      internal = true;
      default =
        if cfg.allowAnyOperator then
          (filterAttrs (_: config: elem self.team config.teams) cfg.users)
        else
          { ${self.defaultOperator} = cfg.users.${self.defaultOperator}; };
    };
  };

  config = {
    users.mutableUsers = false;
    users.groups.operator = { };
    security.tpm2.enable = true;

    users.users = mapAttrs (_: mkOperator) cfg.allowedUsers;
  };
}
