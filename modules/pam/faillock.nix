# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# ANSSI R52 / R64 — brute-force protection for local authentication
# (login, su, sudo, sshd, screen lock).
#
# pam_faillock keeps a per-account counter in /var/run/faillock/;
# after `deny` consecutive failures authentication is refused for
# `unlockTime` seconds. An admin can unlock manually with
# `faillock --reset <user>`.
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
    ;
  cfg = config.securix.pam.faillock;

  commonArgs = [
    "silent"
    "deny=${toString cfg.deny}"
    "unlock_time=${toString cfg.unlockTime}"
  ]
  ++ lib.optional cfg.auditLog "audit";

  faillockModule = "${pkgs.linux-pam}/lib/security/pam_faillock.so";
in
{
  options.securix.pam.faillock = {
    enable = mkEnableOption "account lockout via pam_faillock";

    deny = mkOption {
      type = types.ints.positive;
      default = 5;
      description = ''
        Number of consecutive authentication failures before the
        account is locked. ANSSI recommends a value between 3 and
        10 depending on the operational context.
      '';
    };

    unlockTime = mkOption {
      type = types.ints.unsigned;
      default = 900; # 15 minutes
      description = ''
        Seconds after the last failure before the lock expires
        automatically. Set to 0 to require manual admin unlock
        (`faillock --reset <user>`).
      '';
    };

    auditLog = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Emit success / failure authentication events to auditd
        (recommended when `securix.audit.enable = true`).
      '';
    };

    services = mkOption {
      type = types.listOf types.str;
      default = [
        "login"
        "sshd"
        "sudo"
        "su"
        "swaylock"
      ];
      description = ''
        PAM services to wire pam_faillock into. Each listed service
        runs `pam_faillock preauth` early in its `auth` stack and
        `pam_faillock authfail` at the end to update the counter.
      '';
    };
  };

  config = mkIf cfg.enable {
    security.pam.services = genAttrs cfg.services (_: {
      rules.auth = {
        faillock-preauth = {
          # Runs before any other auth module. If the account is
          # already locked, denies immediately and stops the stack.
          order = 9000;
          control = "required";
          modulePath = faillockModule;
          args = [ "preauth" ] ++ commonArgs;
        };

        faillock-authfail = {
          # Runs after all auth modules (incl. pam_deny at 12400).
          # Increments the counter for this user and kills the stack.
          order = 13000;
          control = "[default=die]";
          modulePath = faillockModule;
          args = [ "authfail" ] ++ commonArgs;
        };
      };

      rules.account = {
        # The account phase also consults faillock so that a locked
        # user cannot fall through to the unix account module.
        faillock = {
          order = 10500;
          control = "required";
          modulePath = faillockModule;
        };
      };
    });
  };
}
