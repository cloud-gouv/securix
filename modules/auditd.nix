# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: 2026 Alexander McHugh <alexanderedwardmchugh@gmail.com>
#
# SPDX-License-Identifier: MIT

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.securix.audit;
  inherit (lib)
    concatMap
    concatMapStringsSep
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  # Emit one rule per ABI. Without the b32 variant, a process can avoid
  # every syscall rule by going through the 32-bit compatibility layer.
  # `syscalls.b32` lists the names that differ or are missing on i386.
  mkSyscallRule =
    {
      key,
      syscalls,
      filters ? "",
    }:
    map
      (
        arch:
        let
          names = syscalls.${arch} or syscalls.common;
        in
        "-a always,exit -F arch=${arch} ${concatMapStringsSep " " (s: "-S ${s}") names}"
        + lib.optionalString (filters != "") " ${filters}"
        + " -k ${key}"
      )
      [
        "b64"
        "b32"
      ];

  # Based on ANSSI-BP-028 v2.0, R73 (log system activity with auditd).
  # Adjusted for NixOS: binaries live in the Nix store, so module loading
  # is tracked at the syscall level instead of by watching /sbin/insmod.
  rules = [
    # Changes to the system configuration.
    "-w /etc/ -p wa -k etc"
    # Reads and changes to the audit trail and audit configuration.
    "-w /var/log/audit/ -p rwa -k audit-log"
    "-w ${lib.getExe' config.security.audit.package "auditctl"} -p x -k audit-tools"
    "-w ${lib.getExe' config.security.audit.package "auditd"} -p x -k audit-tools"
  ]
  ++ concatMap mkSyscallRule [
    {
      key = "exec";
      syscalls.common = [
        "execve"
        "execveat"
      ];
    }
    {
      key = "mount";
      syscalls = {
        common = [
          "mount"
          "umount2"
        ];
        b32 = [
          "mount"
          "umount"
          "umount2"
        ];
      };
    }
    {
      key = "kernel-modules";
      syscalls.common = [
        "init_module"
        "finit_module"
        "delete_module"
      ];
    }
    {
      key = "kexec";
      syscalls = {
        common = [
          "kexec_load"
          "kexec_file_load"
        ];
        # 283 is kexec_load: audit's i386 table spells it "sys_kexec_load",
        # so auditctl rejects the name. i386 has no kexec_file_load.
        b32 = [ "283" ];
      };
    }
    {
      # Direct I/O port and LDT access: rarely legitimate on x86.
      key = "x86-low-level";
      syscalls.common = [
        "ioperm"
        "modify_ldt"
      ];
    }
    {
      key = "ptrace";
      syscalls.common = [ "ptrace" ];
    }
    {
      key = "prctl";
      syscalls.common = [ "prctl" ];
    }
    {
      key = "hostname";
      syscalls.common = [
        "sethostname"
        "setdomainname"
      ];
    }
    {
      # The *at variants are what coreutils actually uses.
      key = "file-deletion";
      syscalls.common = [
        "unlink"
        "unlinkat"
        "rmdir"
        "rename"
        "renameat"
        "renameat2"
      ];
    }
    {
      key = "access-denied";
      syscalls.common = [
        "creat"
        "open"
        "openat"
        "truncate"
        "ftruncate"
      ];
      filters = "-F exit=-EACCES";
    }
    {
      key = "access-denied";
      syscalls.common = [
        "creat"
        "open"
        "openat"
        "truncate"
        "ftruncate"
      ];
      filters = "-F exit=-EPERM";
    }
  ];
in
{
  options.securix.audit = {
    enable = mkEnableOption "system activity auditing with auditd (ANSSI R73)";

    adminEmail = mkOption {
      type = types.str;
      description = "Email address that receives low disk space alerts for the audit log.";
    };

    lockRules = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Make the audit configuration immutable until the next reboot
        (`auditctl -e 2`), as ANSSI R73 recommends. Even root can then no
        longer remove rules or disable auditing at runtime.

        While enabled, a system switch cannot reload the audit rules: a new
        rule set only takes effect after a reboot.
      '';
    };

    extraRules = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "-w /var/lib/secrets/ -p rwa -k secrets" ];
      description = "Additional audit rules, appended after the Sécurix rule set.";
    };
  };

  config = mkIf cfg.enable {
    security.auditd = {
      enable = true;
      settings = {
        space_left = "10%";
        space_left_action = "ignore";
        admin_space_left = "5%";
        admin_space_left_action = "email";
        action_mail_acct = cfg.adminEmail;
        num_logs = 10;
        max_log_file = 100;
        max_log_file_action = "rotate";
      };
    };

    security.audit = {
      enable = if cfg.lockRules then "lock" else true;
      rules = rules ++ cfg.extraRules;
      # Rules load early in boot, but auditd only starts once /var is
      # mounted; until then the kernel queues events, and anything past the
      # backlog limit is lost. The default of 1024, and even CIS's 8192, drop
      # thousands of events on every boot. Queued events are freed once
      # auditd drains them, so a larger limit only costs memory briefly.
      backlogLimit = lib.mkDefault 32768;
    };

    # The rules load before auditd.service creates /var/log/audit. A watch on
    # a missing directory makes auditctl abort, leaving no rules loaded at all.
    systemd.services.audit-rules-nixos = {
      unitConfig.RequiresMountsFor = [ "/var/log" ];
      serviceConfig.ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p -m 0700 /var/log/audit";
    };
  };
}
