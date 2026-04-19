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
    enable = mkEnableOption "la journalisation des évenements à des fins d'audit";

    adminEmail = mkOption {
      type = types.str;
      description = "Email à qui envoyer les alertes d'espace disque";
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
        # ====================================================================
        # ANSSI-aligned audit ruleset (R74 – Audit policy)
        # See https://cyber.gouv.fr/publications/recommandations-de-securite-relatives-un-systeme-gnulinux
        # ====================================================================

        # --- Track audit subsystem itself (tamper detection) ---
        "-w /etc/audit/ -p wa -k audit-config"
        "-w /etc/libaudit.conf -p wa -k audit-config"
        "-w /etc/audisp/ -p wa -k audit-config"
        "-w /var/log/audit/ -p wa -k audit-logs"

        # --- Track process execution (all execve) ---
        "-a always,exit -F arch=b64 -S execve -k exec"
        "-a always,exit -F arch=b32 -S execve -k exec"

        # --- Track privilege escalation (setuid/setgid family) ---
        "-a always,exit -F arch=b64 -S setuid -S setgid -S setreuid -S setregid -S setresuid -S setresgid -k privilege-escalation"
        "-a always,exit -F arch=b32 -S setuid -S setgid -S setreuid -S setregid -S setresuid -S setresgid -k privilege-escalation"

        # --- Track mount/unmount operations ---
        "-a always,exit -F arch=b64 -S mount -S umount2 -k mount"
        "-a always,exit -F arch=b32 -S mount -S umount -S umount2 -k mount"

        # --- Track kernel module loading/unloading ---
        "-a always,exit -F arch=b64 -S init_module -S finit_module -S delete_module -k kernel-module"
        "-a always,exit -F arch=b32 -S init_module -S finit_module -S delete_module -k kernel-module"
        "-w /etc/modprobe.conf -p wa -k modprobe"
        "-w /etc/modprobe.d/ -p wa -k modprobe"
        "-w /etc/modules-load.d/ -p wa -k modprobe"

        # --- Track kexec (live kernel replacement) ---
        "-a always,exit -F arch=b64 -S kexec_load -S kexec_file_load -k kexec"

        # --- Track shared memory operations ---
        "-a always,exit -F arch=b64 -S shmget -S shmat -S shmdt -S shmctl -k shm"
        "-a always,exit -F arch=b32 -S ipc -k shm"

        # --- Track USB / removable devices (evil-maid vector) ---
        "-w /sys/bus/usb/ -p wa -k usb-devices"

        # --- Track Thunderbolt (DMA-capable bus) ---
        "-w /sys/bus/thunderbolt/ -p wa -k thunderbolt"

        # --- Track network interface / configuration changes ---
        "-a always,exit -F arch=b64 -S sethostname -S setdomainname -k hostname-change"
        "-w /etc/hosts -p wa -k network-config"
        "-w /etc/resolv.conf -p wa -k network-config"
        "-w /etc/NetworkManager/ -p wa -k network-config"
        "-w /etc/systemd/network/ -p wa -k network-config"
        "-w /etc/nftables.conf -p wa -k firewall-config"

        # --- Track PAM / authentication subsystem changes ---
        "-w /etc/pam.d/ -p wa -k pam-config"
        "-w /etc/security/ -p wa -k pam-config"
        "-w /etc/u2f-mappings -p wa -k u2f-config"

        # --- Track sudo / escalation configuration ---
        "-w /etc/sudoers -p wa -k sudo-config"
        "-w /etc/sudoers.d/ -p wa -k sudo-config"

        # --- Track time changes (forensic timeline integrity) ---
        "-a always,exit -F arch=b64 -S adjtimex -S settimeofday -S clock_settime -k time-change"
        "-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S clock_settime -S stime -k time-change"
        "-w /etc/localtime -p wa -k time-change"
      ]
      ++ cfg.extraRules;
    };
  };
}
