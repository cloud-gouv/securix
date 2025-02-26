# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, lib, pkgs, ... }:
let
  cfg = config.securix.ssh.tpm-agent;
  inherit (lib) mkEnableOption mkIf mkMerge;
in
{ 
  options.securix.ssh.tpm-agent = {
    hostKeys = mkEnableOption "the sealing of SSH host keys in the TPM";
    sshKeys = mkEnableOption "the sealing of SSH keys in the TPM";
  };

  config = mkMerge [
    (mkIf cfg.sshKeys {
      systemd.user.services.ssh-tpm-agent = {
        unitConfig = {
          Description = "SSH TPM agent service";
          Documentation = "man:ssh-agent(1) man:ssh-add(1) man:ssh(1)";
          Requires = "ssh-tpm-agent.socket";
          ConditionEnvironment = "!SSH_AGENT_PID";
        };
        serviceConfig = {
          Environment = "SSH_AUTH_SOCK=%t/ssh-tpm-agent.socket";
          ExecStart = "${pkgs.ssh-tpm-agent}/bin/ssh-tpm-agent";
          PassEnvironment = "SSH_AGENT_PID";
          SuccessExitStatus = 2;
          Type = "simple";
        };
      };

      systemd.user.sockets.ssh-tpm-agent = {
        unitConfig = {
          Description = "SSH TPM agent socket";
          Documentation = "man:ssh-agent(1) man:ssh-add(1) man:ssh(1)";
        };

        socketConfig = {
          ListenStream = "%t/ssh-tpm-agent.sock";
          SocketMode = "0600";
          Service = "ssh-tpm-agent.service";
        };

        wantedBy = [ "sockets.target" ];
      };
    })
    (mkIf cfg.hostKeys {
      # TODO: figure out how to use properly TPM keys when unlocking the PSK at boot.
      systemd.services.ssh-genkeys = {
        description = "SSH keys generation";

        unitConfig.ConditionPathExists = [
          "|!/etc/ssh/ssh_host_rsa_key.pub"
          "|!/etc/ssh/ssh_host_rsa_key"
        ];

        serviceConfig = {
          ExecStart = "${pkgs.openssh}/bin/ssh-keygen -A";
          Type = "oneshot";
          RemainAfterExit = "yes";
        };

        wantedBy = [ "network.target" ];
      };

      systemd.services.ssh-tpm-genkeys = {
        description = "SSH TPM Key Generation";

        unitConfig = {
          ConditionPathExists = [
            "|!/etc/ssh/ssh_tpm_host_ecdsa_key.pub"
            "|!/etc/ssh/ssh_tpm_host_ecdsa_key.tpm"
          ];
        };

        serviceConfig = {
          ExecStart = "${pkgs.ssh-tpm-agent}/bin/ssh-tpm-keygen -A";
          Type = "oneshot";
          RemainAfterExit = "yes";
        };

        wantedBy = [ "network.target" ];
      };

      systemd.sockets.ssh-tpm-agent = {
        unitConfig = {
          Description = "SSH TPM agent socket";
          Documentation = "man:ssh-agent(1) man:ssh-add(1) man:ssh(1)";
        };

        socketConfig = {
          ListenStream = "/var/tmp/ssh-tpm-agent.sock";
          SocketMode = "0600";
          Service = "ssh-tpm-agent.service";
        };

        wantedBy = [ "sockets.target" ];
      };

      systemd.services.ssh-tpm-agent = {
        unitConfig = {
          ConditionEnvironment = "!SSH_AGENT_PID";
          Description = "ssh-tpm-agent system service";
          Documentation = "man:ssh-agent(1) man:ssh-add(1) man:ssh(1)";
          Wants = [ "ssh-tpm-genkeys.service" ];
          After = [
            "ssh-tpm-genkeys.service"
            "network.target"
            "sshd.target"
          ];

          Requires = [ "ssh-tpm-agent.socket" ];
        };

        serviceConfig = {
          ExecStart = "${pkgs.ssh-tpm-agent}/bin/ssh-tpm-agent --key-dir /etc/ssh";
          PassEnvironment = "SSH_AGENT_PID";
          KillMode = "process";
          Restart = "always";
        };

        wantedBy = [ "multi-user.target" ];
      };
      services.openssh.hostKeys = [];
      services.openssh.extraConfig = lib.mkAfter ''
        HostKeyAgent /var/tmp/ssh-tpm-agent.sock
        HostKey /etc/ssh/ssh_tpm_host_ecdsa_key
      '';
    })
  ];
}
