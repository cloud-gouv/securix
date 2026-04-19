# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# ANSSI R74 — Journalisation des activités interactives des administrateurs.
#
# pam_tty_audit(8) demande au noyau d'enregistrer toutes les frappes clavier
# saisies dans un TTY après authentification, pour les utilisateurs listés
# dans `enable=`. Les événements sont routés vers auditd (qui doit être
# activé via `securix.audit.enable = true`).
#
# Complément naturel à la règle R74 `-a always,exit -F arch=b64 -S execve`
# (activée par le module `securix.audit`) : execve trace les commandes
# lancées, pam_tty_audit trace les *frappes* (y compris les commandes
# tapées dans un shell interactif avant d'être exécutées, les éditions
# vim, les mots de passe entrés dans une application, etc.).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    genAttrs
    concatStringsSep
    optional
    ;
  cfg = config.securix.pam.ttyAudit;

  ttyAuditModule = "${pkgs.linux-pam}/lib/security/pam_tty_audit.so";

  args =
    optional (cfg.enableFor != [ ]) "enable=${concatStringsSep "," cfg.enableFor}"
    ++ optional (cfg.disableFor != [ ]) "disable=${concatStringsSep "," cfg.disableFor}"
    ++ optional cfg.logPassword "log_passwd";
in
{
  options.securix.pam.ttyAudit = {
    enable = mkEnableOption "keystroke auditing via pam_tty_audit";

    enableFor = mkOption {
      type = types.listOf types.str;
      default = [ "*" ];
      description = ''
        List of user names for which TTY input should be audited. Use
        `[ "*" ]` (default) to audit everyone — recommended for admin
        workstations per ANSSI. Use `[ "root" ]` to only audit root
        sessions, or a specific list for targeted auditing.
      '';
      example = [ "root" "alice" ];
    };

    disableFor = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        List of user names to explicitly exclude from TTY auditing, even
        if they match `enableFor`. Useful to carve out service accounts.
      '';
      example = [ "nixbld" ];
    };

    logPassword = mkOption {
      type = types.bool;
      default = false;
      description = ''
        When true, also record input during password prompts (terminal
        echo-off mode). **Strongly discouraged** — audit logs would
        contain plaintext passwords, defeating the purpose of hashing
        them in /etc/shadow. Left here for explicit opt-in only.
      '';
    };

    services = mkOption {
      type = types.listOf types.str;
      default = [
        "login"
        "sshd"
        "su"
        "sudo"
      ];
      description = ''
        PAM services to wire `pam_tty_audit` into. Only services that
        allocate a TTY should be listed (login, sshd, su, sudo). Adding
        it to non-TTY services like swaylock or polkit is a no-op.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Enforce auditd presence so the events actually land somewhere.
    assertions = [
      {
        assertion = config.security.auditd.enable or config.securix.audit.enable or false;
        message = ''
          `securix.pam.ttyAudit.enable = true` requires auditd to be enabled,
          otherwise pam_tty_audit events are discarded. Set either
          `securix.audit.enable = true` (recommended) or
          `security.auditd.enable = true`.
        '';
      }
    ];

    security.pam.services = genAttrs cfg.services (_: {
      rules.session.tty-audit = {
        # Runs in the session phase, after authentication succeeded.
        # Kernel starts recording TTY input from this point on.
        order = 10500;
        control = "required";
        modulePath = ttyAuditModule;
        inherit args;
      };
    });
  };
}
