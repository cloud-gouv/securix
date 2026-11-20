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
  inherit (lib) mkEnableOption mkIf mkPackageOption;

  runDir = "/run/securix-hints";
  controlSocket = "${runDir}/control.sock";
  consumerSocket = "${runDir}/consumer.sock";
in
{
  options.securix.hints = {
    enable = mkEnableOption "the Sécurix hint subsystem";
    package = mkPackageOption pkgs "securix-hints" { };
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
