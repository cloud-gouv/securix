# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# ANSSI R32 / CIS 5.4.5 — Politique d'âge des mots de passe et
# verrouillage des comptes dormants (login.defs).
#
# Sécurix n'impose aujourd'hui aucune expiration : les valeurs NixOS
# par défaut sont PASS_MAX_DAYS=99999 (≈ 273 ans) et INACTIVE=-1
# (jamais). Un compte créé hier et laissé dormant pendant dix ans
# reste utilisable avec le même mot de passe. ANSSI R32 et CIS 5.4.5
# exigent une rotation bornée et un verrouillage automatique des
# comptes inactifs.
#
# Ce module définit quatre paramètres dans /etc/login.defs :
#
#   PASS_MAX_DAYS 180   âge max d'un mot de passe avant rotation
#   PASS_MIN_DAYS 1     délai minimal avant un 2ᵉ changement
#   PASS_WARN_AGE 14    avertissement 2 semaines avant expiration
#   INACTIVE      30    verrou du compte après 30 j sans login
#
# === Pourquoi 180 jours (6 mois) et pas 90 jours ===
#
# L'ANSSI R32 v2.0 exige l'expiration mais ne fige pas la durée ;
# l'implémenter "classique" (90 jours) copie les politiques Windows
# héritées des années 2000. Cette fréquence est aujourd'hui
# majoritairement considérée comme contre-productive :
#
# 1. NIST SP 800-63B (rev. 3, 2017) — section 5.1.1.2 — recommande
#    explicitement de NE PAS forcer de rotation périodique en
#    l'absence de compromission avérée. La raison : des rotations
#    trop fréquentes poussent l'utilisateur vers des patterns
#    prédictibles (Password!2024 → Password!2025, Hiver2024 →
#    Printemps2024), ce qui annule le gain de sécurité.
#
# 2. Zhang, Monrose, Reiter (ACM CCS 2010, "The security of modern
#    password expiration : an algorithmic framework and empirical
#    analysis") analyse les transformations effectuées par 51 141
#    comptes universitaires après rotation forcée. Un attaquant qui
#    connaît l'ancien mot de passe retrouve le nouveau en ≤ 5
#    devinettes dans 41 % des cas offline et 17 % online — la
#    rotation périodique ne protège donc pas contre un attaquant
#    patient.
#
# 3. Microsoft a supprimé l'expiration par défaut des Group Policy
#    Windows (Windows 10 1903 baseline, mai 2019) en citant
#    explicitement les travaux ci-dessus.
#
# 4. Contexte Sécurix : l'authentification primaire est FIDO2/U2F
#    (cf. modules/pam/u2f.nix, PRs #134 et #135). Le mot de passe
#    sert de fallback (sudo, recovery après perte de YubiKey). La
#    fenêtre d'exploitation d'un mot de passe seul est donc déjà
#    réduite par la possession du facteur physique.
#
# 5. Défense en profondeur déjà en place :
#      - pam_faillock (PR #138)   verrou après 5 tentatives échouées
#      - pam_pwquality (PR #151)  minlen=12, minclass=3, dictcheck
#      - tty-audit (PR #138)      traçabilité des frappes root
#    Un attaquant qui tente un brute-force en ligne frappe faillock
#    bien avant d'épuiser l'espace des mots de passe 12+ caractères.
#
# Le choix de 180 jours est donc un compromis assumé :
#
#   * satisfait l'obligation réglementaire ANSSI R32 (expiration bornée) ;
#   * évite les anti-patterns documentés de la rotation trop fréquente ;
#   * s'aligne sur la durée pratique adoptée par des organisations
#     sécurité-sensibles comparables (observé publiquement chez Google,
#     GitLab, Stripe en 2024) ;
#   * laisse de la marge face à une rotation d'urgence déclenchée
#     par un détecteur d'anomalie ou une suspicion de compromission.
#
# Un opérateur qui préfère la valeur ANSSI "historique" de 90 jours
# peut la restaurer sans exclure la règle :
#
#   security.loginDefs.settings.PASS_MAX_DAYS = lib.mkForce 90;
#
# === Pourquoi PASS_MIN_DAYS = 1 ===
#
# Empêche un utilisateur forcé de changer de mot de passe de faire
# immédiatement un 2ᵉ changement pour récupérer l'ancien (cycle
# trivial qui annule l'intérêt de l'expiration). 1 jour suffit à
# décourager la pratique sans bloquer une rotation d'urgence
# légitime (l'admin peut toujours utiliser `chage -d 0 <user>`).
#
# === Pourquoi INACTIVE = 30 ===
#
# Un compte admin inutilisé pendant 30 jours est probablement un
# ancien collaborateur, un compte de secours oublié ou une identité
# de pré-production restée active. Le verrou automatique limite la
# surface d'un compte fantôme. Les comptes système (services,
# automation) ne sont pas concernés : `INACTIVE` ne s'applique
# qu'aux comptes dont le mot de passe peut expirer — les comptes
# créés avec `useradd -M` ou sans shadow valide restent inchangés.
#
# === Effet sur les comptes existants ===
#
# Important : modifier /etc/login.defs ne réécrit PAS les champs
# d'expiration des comptes déjà créés (stockés dans /etc/shadow
# colonnes 5 à 7). Un compte créé avant l'activation du module reste
# sur PASS_MAX_DAYS=-1 (jamais expirer), parce que useradd lit
# login.defs à la création uniquement.
#
# Pour aligner les comptes existants :
#
#   chage -M 180 -m 1 -W 14 -I 30 <user>           # par compte
#   awk -F: '$2 ~ /^\$/ {print $1}' /etc/shadow \  # batch : tous les
#     | xargs -n1 chage -M 180 -m 1 -W 14 -I 30    # comptes locaux
#
# Sécurix étant une distribution déployée fresh (images reproductibles
# via nixos-install), ce cas est marginal : les comptes sont créés
# avec les valeurs du nouveau login.defs. Le checkScript R32 signale
# en non-bloquant les comptes /etc/shadow qui auraient dérivé.
{
  R32 = {
    name = "R32_PasswordAgingAndLockout";
    anssiRef = "R32 – Expiration des mots de passe et verrouillage des comptes inactifs";
    description = ''
      Configure password aging (PASS_MAX_DAYS / MIN / WARN) and
      inactive-account lockout (INACTIVE) in /etc/login.defs.
    '';
    severity = "intermediary";
    category = "base";
    tags = [ "password-aging" ];

    config =
      { lib, ... }:
      {
        # mkDefault so an operator can restore 90 d (or any other
        # value) without mkForce plumbing, while keeping the rule
        # enabled for audit / compliance reporting.
        security.loginDefs.settings = {
          PASS_MAX_DAYS = lib.mkDefault 180;
          PASS_MIN_DAYS = lib.mkDefault 1;
          PASS_WARN_AGE = lib.mkDefault 14;
          INACTIVE = lib.mkDefault 30;
        };
      };

    checkScript =
      pkgs:
      pkgs.writeShellScript "check-R32" ''
        set -u
        status=0
        defs=/etc/login.defs

        check() {
          local key="$1" expected="$2"
          local actual
          actual=$(${pkgs.gnugrep}/bin/grep -E "^[[:space:]]*$key[[:space:]]+" "$defs" 2>/dev/null \
                   | ${pkgs.gawk}/bin/awk '{print $2}' \
                   | ${pkgs.coreutils}/bin/head -n1)
          if [ -z "$actual" ]; then
            echo "FAIL: $key absent dans $defs"
            status=1
          elif [ "$actual" != "$expected" ]; then
            echo "FAIL: $key = $actual (attendu $expected)"
            status=1
          else
            echo "PASS: $key = $actual"
          fi
        }

        check PASS_MAX_DAYS 180
        check PASS_MIN_DAYS 1
        check PASS_WARN_AGE 14
        check INACTIVE 30

        # Informatif (non bloquant) : signale les entrées /etc/shadow
        # où un compte à mot de passe haché a PASS_MAX_DAYS non-fixé
        # ou > 180. Ce sont les comptes qui existaient avant que la
        # politique ne soit en vigueur et qui doivent encore être
        # alignés par `chage -M 180 -m 1 -W 14 -I 30 <user>`.
        if [ -r /etc/shadow ]; then
          stale=$(${pkgs.gawk}/bin/awk -F: '
            $2 ~ /^\$/ && ($5 == "" || $5 == "99999" || $5+0 > 180) { print $1 }
          ' /etc/shadow 2>/dev/null | ${pkgs.coreutils}/bin/head -n5)
          if [ -n "$stale" ]; then
            echo "INFO: comptes existants avec PASS_MAX_DAYS > 180 dans /etc/shadow :"
            echo "$stale" | ${pkgs.gnused}/bin/sed 's/^/  - /'
            echo "  fix : chage -M 180 -m 1 -W 14 -I 30 <user>"
          fi
        fi

        exit $status
      '';
  };
}
