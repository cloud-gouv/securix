# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# Mail Transfer Agent en sortie seulement, pour les notifications système.
#
# Un poste Sécurix a besoin d'un moyen pour acheminer les mails
# administratifs (alertes d'espace disque auditd, alertes de
# verrouillage pam_faillock, erreurs cron, notifications d'échec
# smartmontools / mdadm / systemd, …). Faire tourner un MTA complet
# (postfix, opensmtpd) est overkill et expose un démon réseau ; on
# utilise plutôt `msmtp` en remplaçant de `sendmail` qui transfère
# chaque mail local vers un relais SMTP amont. Aucun listener n'est
# ouvert.
#
# Ce module configure seulement le relais — *qui* génère les mails
# est décidé par d'autres modules (securix.audit, securix.pam.faillock,
# etc.).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.securix.mta;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    optionalAttrs
    concatStringsSep
    mapAttrsToList
    ;
in
{
  options.securix.mta = {
    enable = mkEnableOption ''
      un MTA en sortie seulement (msmtp) qui relaie les notifications
      système vers un serveur SMTP amont. msmtp est invoqué en
      remplacement de `sendmail` ; il **n'écoute sur aucun port**
    '';

    fromAddress = mkOption {
      type = types.str;
      default = "root@${config.networking.hostName or "securix"}";
      defaultText = lib.literalExpression ''"root@\${config.networking.hostName}"'';
      description = ''
        Adresse `From:` utilisée sur les mails sortants. Les
        destinataires la verront comme expéditeur, donc la rendre
        descriptive (ex. `securix-ops-laptop-012@example.local`).
      '';
    };

    upstream = {
      host = mkOption {
        type = types.str;
        example = "smtp.example.local";
        description = "Nom d'hôte ou IP du relais SMTP amont.";
      };
      port = mkOption {
        type = types.port;
        default = 587;
        description = ''
          Port SMTP amont. Conventions :
            * 587 — submission (STARTTLS, authentifié)
            * 465 — SMTPS (TLS implicite)
            * 25  — SMTP en clair (relais, typiquement non authentifié)
        '';
      };
      tls = mkOption {
        type = types.bool;
        default = true;
        description = "Exige TLS lors de la connexion à l'amont.";
      };
      tlsCertcheck = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Valide le certificat TLS du serveur amont contre le bundle
          CA système. À désactiver uniquement pour tester contre des
          relais internes auto-signés (et ajouter plutôt la CA à
          `security.pki.certificateFiles` — c'est plus propre).
        '';
      };
      auth = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              user = mkOption {
                type = types.str;
                description = "Nom d'utilisateur SMTP (les usernames ne sont pas traités comme des secrets).";
              };
              passwordFile = mkOption {
                type = types.path;
                description = ''
                  Chemin vers un fichier contenant le mot de passe SMTP
                  sur une seule ligne. Typiquement câblé via agenix :
                  `age.secrets.mta-password.path`. Lu à l'exécution par
                  le `passwordeval` de `msmtp`, donc le mot de passe
                  n'arrive jamais dans le Nix store.
                '';
              };
            };
          }
        );
        default = null;
        description = ''
          Authentification SMTP optionnelle. Laisser `null` pour des
          relais non authentifiés (ex. mailhubs internes protégés par
          ACL d'adresse source).
        '';
      };
    };

    aliases = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Alias locaux écrits dans `/etc/aliases`. Au minimum il est
        souhaitable de pointer `root` vers qui reçoit les notifications
        ops :

        ```nix
        securix.mta.aliases.root = "secops@example.local";
        ```

        Si `securix.audit.enable = true`, `securix.audit.adminEmail` est
        un défaut naturel pour cet alias.
      '';
      example = {
        root = "secops@example.local";
      };
    };
  };

  config = mkIf cfg.enable {
    programs.msmtp = {
      enable = true;
      setSendmail = true;
      defaults = {
        aliases = "/etc/aliases";
        tls = if cfg.upstream.tls then "on" else "off";
        tls_starttls = if cfg.upstream.tls && cfg.upstream.port == 587 then "on" else "off";
        tls_certcheck = if cfg.upstream.tlsCertcheck then "on" else "off";
        auth = if cfg.upstream.auth != null then "on" else "off";
        logfile = "/var/log/msmtp.log";
      };
      accounts.default = {
        host = cfg.upstream.host;
        port = cfg.upstream.port;
        from = cfg.fromAddress;
      }
      // optionalAttrs (cfg.upstream.auth != null) {
        user = cfg.upstream.auth.user;
        passwordeval = "${pkgs.coreutils}/bin/cat ${cfg.upstream.auth.passwordFile}";
      };
    };

    environment.etc.aliases.text =
      concatStringsSep "\n" (mapAttrsToList (k: v: "${k}: ${v}") cfg.aliases) + "\n";
  };
}
