# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# ANSSI R29 / CIS 5.4.1 — Politique de qualité pour les mots de passe
# locaux.
#
# Sur Sécurix, la FIDO2/U2F est le facteur d'authentification primaire
# (voir `modules/pam/u2f.nix`) ; le mot de passe reste un **fallback**
# utilisé quand la clé n'est pas présente ou défaillante. C'est
# précisément dans ce cas de repli que la qualité du mot de passe
# compte : perdre sa Yubikey + avoir un mot de passe faible ⇒ tout
# l'édifice s'écroule au premier login.
#
# Ce module configure `pam_pwquality(8)` en `requisite` sur le PAM
# stack `passwd` : chaque tentative de changement de mot de passe
# passe par une batterie de tests (longueur, classes, dictionnaire,
# répétitions). Si le mot de passe proposé est jugé faible, `passwd`
# refuse le changement et demande un autre.
#
# Note : pam_pwquality ne vérifie QUE les nouveaux mots de passe
# entrés via `passwd` / `chpasswd`. Les mots de passe existants
# (pre-déploiement) ne sont PAS relus. Pour forcer un renouvellement
# à tous les comptes, combiner avec PASS_MAX_DAYS dans login.defs.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.securix.pam.pwquality;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    concatLists
    mapAttrsToList
    ;

  pwqConfigLines = [
    "minlen=${toString cfg.minlen}"
    "minclass=${toString cfg.minclass}"
    "retry=${toString cfg.retry}"
    "difok=${toString cfg.difok}"
    "maxrepeat=${toString cfg.maxrepeat}"
    "maxsequence=${toString cfg.maxsequence}"
  ]
  ++ lib.optional cfg.dictcheck "dictcheck=1"
  ++ lib.optional cfg.gecoscheck "gecoscheck=1"
  ++ lib.optional cfg.enforceRoot "enforce_for_root"
  ++ cfg.extraArgs;
in
{
  options.securix.pam.pwquality = {
    enable = mkEnableOption ''
      l'application de la qualité de mot de passe via pam_pwquality
      sur les stacks PAM `passwd` (et optionnellement `chpasswd`,
      `chfn`)
    '';

    minlen = mkOption {
      type = types.ints.positive;
      default = 12;
      description = ''
        Longueur minimale du mot de passe. 12 caractères est la
        recommandation CIS pour les postes d'administration.
      '';
    };

    minclass = mkOption {
      type = types.ints.between 1 4;
      default = 3;
      description = ''
        Nombre minimal de classes de caractères (minuscule,
        majuscule, chiffre, autre) devant apparaître dans le mot
        de passe.
      '';
    };

    retry = mkOption {
      type = types.ints.positive;
      default = 3;
      description = "Nombre de tentatives avant que `passwd` abandonne.";
    };

    difok = mkOption {
      type = types.ints.unsigned;
      default = 5;
      description = ''
        Nombre de caractères qui doivent différer du mot de passe
        précédent. Empêche les incréments triviaux (par ex.
        `Password2024!` → `Password2025!`).
      '';
    };

    maxrepeat = mkOption {
      type = types.ints.positive;
      default = 3;
      description = ''
        Rejette les mots de passe où un même caractère est répété
        plus de ce nombre de fois consécutivement (par ex. `aaaa`).
      '';
    };

    maxsequence = mkOption {
      type = types.ints.positive;
      default = 3;
      description = ''
        Rejette les mots de passe contenant des séquences monotones
        de caractères plus longues que cette valeur (par ex. `abcd`,
        `1234`, `qwer`).
      '';
    };

    dictcheck = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Rejette les mots de passe qui matchent une entrée du
        dictionnaire cracklib. Attrape le pattern classique
        `password123!`.
      '';
    };

    gecoscheck = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Rejette les mots de passe qui contiennent des composants
        du champ GECOS de l'utilisateur (nom, email, login).
      '';
    };

    enforceRoot = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Applique la politique à root aussi. L'ANSSI recommande
        `true` — exempter root est un bypass classique.
      '';
    };

    services = mkOption {
      type = types.listOf types.str;
      default = [
        "passwd"
        "chpasswd"
      ];
      description = ''
        Services PAM dans la phase `password` desquels le check
        pwquality est injecté. Le défaut couvre les points
        d'entrée usuels ; `chfn` est souvent exclu parce qu'il ne
        change que le GECOS, pas le mot de passe lui-même.
      '';
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Arguments bruts supplémentaires pour pam_pwquality, passés
        tels quels. À utiliser pour des réglages non exposés en
        options structurées ci-dessus (par ex. `usercheck=1`,
        `usersubstr=4`, `badwords=...`).
      '';
      example = [
        "usercheck=1"
        "usersubstr=4"
      ];
    };
  };

  config = mkIf cfg.enable {
    # Injecte pam_pwquality en tête de la phase `password` des
    # services PAM listés. `requisite` signifie : si pwquality
    # refuse, le stack entier échoue immédiatement — l'utilisateur
    # voit l'erreur et `passwd` redemande un autre mot de passe
    # (jusqu'à `retry` fois).
    security.pam.services = lib.genAttrs cfg.services (_: {
      rules.password.pwquality = {
        order = 10000; # avant pam_unix password (order 10200)
        control = "requisite";
        modulePath = "${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so";
        args = pwqConfigLines;
      };
    });
  };
}
