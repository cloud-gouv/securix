# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# ANSSI R74 — log interactive administrator activity.
#
# pam_tty_audit(8) tells the kernel to record every keystroke
# typed into a TTY after authentication, for users listed in
# `enable=`. Events are routed to auditd (which must be active
# via `securix.audit.enable = true`).
#
# Complements the R74 `-a always,exit -F arch=b64 -S execve` rule
# in `securix.audit`: `execve` traces *which commands* were
# launched, `pam_tty_audit` traces *what was typed* (including
# commands typed in an interactive shell before they are
# executed, vim edits, passwords entered into applications, etc.).
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
        User names whose TTY input should be audited. Use
        `[ "*" ]` (default) to audit everyone — recommended for
        admin workstations per ANSSI. Use `[ "root" ]` to audit
        only root sessions, or a targeted list.
      '';
      example = [
        "root"
        "alice"
      ];
    };

    disableFor = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        User names explicitly excluded from TTY auditing, even
        if they match `enableFor`. Useful to carve out service
        accounts.
      '';
      example = [ "nixbld" ];
    };

    logPassword = mkOption {
      type = types.bool;
      default = false;
      description = ''
        When true, also record input during password prompts
        (terminal echo-off mode). **Strongly discouraged** —
        audit logs would contain plaintext passwords, defeating
        the purpose of hashing them in /etc/shadow. Kept here
        for explicit opt-in only.
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
        PAM services into which `pam_tty_audit` is wired. Only
        services that allocate a TTY should be listed (login,
        sshd, su, sudo). Adding it to non-TTY services like
        swaylock or polkit is a no-op.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Require auditd, otherwise pam_tty_audit events are discarded.
    assertions = [
      {
        assertion = config.security.auditd.enable or config.securix.audit.enable or false;
        message = ''
          `securix.pam.ttyAudit.enable = true` requires auditd to
          be enabled, otherwise pam_tty_audit events are discarded.
          Set either `securix.audit.enable = true` (recommended) or
          `security.auditd.enable = true`.
        '';
      }
    ];

    security.pam.services = genAttrs cfg.services (_: {
      rules.session.tty-audit = {
        # Runs in the session phase, after successful auth. The
        # kernel starts recording TTY input from this point on.
        order = 10500;
        control = "required";
        modulePath = ttyAuditModule;
        inherit args;
      };
    });
  };
}
