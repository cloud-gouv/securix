# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
let
  cfg = config.securix.audit;
  inherit (lib)
    mkEnableOption
    mkIf
    types
    mkOption
    ;
in
{
  options.securix.audit = {
    enable = mkEnableOption "auditd-based kernel event logging";

    adminEmail = mkOption {
      type = types.str;
      description = "Email address notified when the audit log partition runs low on space.";
    };

    extraRules = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Additional audit rules to append to the default ANSSI-aligned ruleset.
      '';
    };
  };

  config = mkIf cfg.enable {
    # R33 ANSSI
    security.auditd.enable = true;
    environment.etc."audit/auditd.conf".text = ''
      space_left = 10%
      space_left_action = ignore
      admin_space_left = 5%
      admin_space_left_action = email
      action_mail_acct = ${cfg.adminEmail}
      num_logs = 10
      max_log_file = 100
      max_log_file_action = rotate
    '';
    security.audit = {
      enable = true;
      rules = [
        # ANSSI NT28 v2.0 R73 — system activity audit.
        # See https://cyber.gouv.fr/publications/recommandations-de-securite-relatives-un-systeme-gnulinux
        # Audit subsystem tamper detection.
        "-w /etc/audit/ -p wa -k audit-config"
        "-w /etc/libaudit.conf -p wa -k audit-config"
        "-w /etc/audisp/ -p wa -k audit-config"
        "-w /var/log/audit/ -p wa -k audit-logs"
        # Process execution.
        "-a always,exit -F arch=b64 -S execve -k exec"
        "-a always,exit -F arch=b32 -S execve -k exec"
        # Privilege escalation (setuid/setgid family).
        "-a always,exit -F arch=b64 -S setuid -S setgid -S setreuid -S setregid -S setresuid -S setresgid -k privilege-escalation"
        "-a always,exit -F arch=b32 -S setuid -S setgid -S setreuid -S setregid -S setresuid -S setresgid -k privilege-escalation"
        # Mount/unmount operations.
        "-a always,exit -F arch=b64 -S mount -S umount2 -k mount"
        "-a always,exit -F arch=b32 -S mount -S umount -S umount2 -k mount"
        # Kernel module load/unload + modprobe config.
        "-a always,exit -F arch=b64 -S init_module -S finit_module -S delete_module -k kernel-module"
        "-a always,exit -F arch=b32 -S init_module -S finit_module -S delete_module -k kernel-module"
        "-w /etc/modprobe.conf -p wa -k modprobe"
        "-w /etc/modprobe.d/ -p wa -k modprobe"
        "-w /etc/modules-load.d/ -p wa -k modprobe"
        # kexec (live kernel replacement).
        "-a always,exit -F arch=b64 -S kexec_load -S kexec_file_load -k kexec"
        # Shared memory IPC.
        "-a always,exit -F arch=b64 -S shmget -S shmat -S shmdt -S shmctl -k shm"
        "-a always,exit -F arch=b32 -S ipc -k shm"
        # USB / removable devices (evil-maid vector).
        "-w /sys/bus/usb/ -p wa -k usb-devices"
        # Thunderbolt (DMA-capable bus).
        "-w /sys/bus/thunderbolt/ -p wa -k thunderbolt"
        # Network interface / configuration changes.
        "-a always,exit -F arch=b64 -S sethostname -S setdomainname -k hostname-change"
        "-w /etc/hosts -p wa -k network-config"
        "-w /etc/resolv.conf -p wa -k network-config"
        "-w /etc/NetworkManager/ -p wa -k network-config"
        "-w /etc/systemd/network/ -p wa -k network-config"
        "-w /etc/nftables.conf -p wa -k firewall-config"
        # PAM / authentication subsystem changes.
        "-w /etc/pam.d/ -p wa -k pam-config"
        "-w /etc/security/ -p wa -k pam-config"
        "-w /etc/u2f-mappings -p wa -k u2f-config"
        # sudo / escalation configuration.
        "-w /etc/sudoers -p wa -k sudo-config"
        "-w /etc/sudoers.d/ -p wa -k sudo-config"
        # Time changes (forensic timeline integrity).
        "-a always,exit -F arch=b64 -S adjtimex -S settimeofday -S clock_settime -k time-change"
        "-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S clock_settime -S stime -k time-change"
        "-w /etc/localtime -p wa -k time-change"
      ] ++ cfg.extraRules;
    };
  };
}
