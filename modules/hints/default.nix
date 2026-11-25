# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.securix.hints;
  inherit (lib)
    mkIf
    mkOption
    mkPackageOption
    types
    ;

  runDir = "/run/securix-hints";
  controlSocket = "${runDir}/control.sock";
  consumerSocket = "${runDir}/consumer.sock";
in
{
  imports = [ ./kernel-reboot.nix ];

  options.securix.hints = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enable the Sécurix hint subsystem. The updater and the manual upgrade
        send their notices as hints, so a machine without the daemon shows no
        update notice.
      '';
    };
    package = mkPackageOption pkgs "securix-hints" { };

    autoReboot = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Reboot the machine when a critical hint stays for a long time. The hint
        appears in every case. Only the automatic reboot changes.
      '';
    };

    autoRebootAfterSeconds = mkOption {
      type = types.int;
      default = 8 * 60 * 60;
      description = ''
        How long a critical hint waits before the machine reboots. The delay
        starts when the agent first sees the hint as critical.
      '';
    };

    criticalSource = mkOption {
      type = types.str;
      default = "securix-kernel";
      description = ''
        The producer that can make the machine reboot itself. A hint from
        another producer never reboots a machine.
      '';
    };
  };

  config = mkIf cfg.enable {
    users.groups.securix-hints-control = { };

    environment.systemPackages = [ cfg.package ];

    systemd.tmpfiles.rules = [ "d ${runDir} 0755 root root -" ];

    systemd.sockets.securix-hintd-control = {
      description = "Sécurix hint daemon control socket";
      wantedBy = [ "sockets.target" ];

      socketConfig = {
        ListenStream = controlSocket;
        SocketMode = "0600";
        SocketUser = "root";
        SocketGroup = "securix-hints-control";
        FileDescriptorName = "control";
        Service = "securix-hintd.service";
      };
    };

    systemd.sockets.securix-hintd-consumer = {
      description = "Sécurix hint daemon consumer socket";
      wantedBy = [ "sockets.target" ];

      socketConfig = {
        ListenStream = consumerSocket;
        SocketMode = "0666";
        SocketUser = "root";
        SocketGroup = "root";
        FileDescriptorName = "consumer";
        Service = "securix-hintd.service";
      };
    };

    systemd.user.services.securix-hint-agent = {
      description = "Sécurix hint agent";

      environment = {
        SECURIX_HINTS_AUTO_REBOOT = if cfg.autoReboot then "1" else "0";
        SECURIX_HINTS_AUTO_REBOOT_AFTER_SECONDS = toString cfg.autoRebootAfterSeconds;
        SECURIX_HINTS_CRITICAL_SOURCE = cfg.criticalSource;
      };

      path = [
        pkgs.systemd
        pkgs.util-linux
      ];
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/securix-hint-agent --socket ${consumerSocket}";
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    systemd.services.securix-hintd = {
      description = "Sécurix hint daemon";
      wantedBy = [ "multi-user.target" ];
      requires = [
        "securix-hintd-control.socket"
        "securix-hintd-consumer.socket"
      ];
      after = [
        "securix-hintd-control.socket"
        "securix-hintd-consumer.socket"
      ];

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/securix-hintd ${controlSocket} ${consumerSocket}";
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 5;

        DynamicUser = true;
        RuntimeDirectory = "securix-hintd";
        RuntimeDirectoryMode = "0700";
        # A restart must keep the hints.
        RuntimeDirectoryPreserve = "yes";

        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        RestrictAddressFamilies = [ "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        UMask = "0077";
      };
    };
  };
}
