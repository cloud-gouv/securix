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
        # TODO:
        # track audit itself accesses
        # track shm accesses
        # track mount/unmount
        # track usb keys accesses
        # track kernel module loading
        # track kexec operations
        # track network cards changes
        # track thunderbolt changes
        # This tracks only all execve for now, which is not that bad.
        "-a exit,always -F arch=b64 -S execve"
      ];
    };
  };
}
