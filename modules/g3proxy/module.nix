# SPDX-FileCopyrightText: 2025 Elias Coppens <elias.coppens@numerique.gouv.fr>
# SPDX-FileContributor: Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

# Remove this when https://github.com/NixOS/nixpkgs/pull/378059 is merged and we upgraded nixpkgs.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.g3proxy;

  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    literalExpression
    types
    ;

  settingsFormat = pkgs.formats.yaml { };

  package = cfg.package;
in
{
  options.services.g3proxy = {
    enable = mkEnableOption "g3proxy";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix { };
    };

    settings = mkOption {
      type = settingsFormat.type;
      default = { };
      example = literalExpression ''
        {
          server = [{
            name = "test";
            escaper = "default";
            type = "socks_proxy";
            listen = {
              address = "[::]:10086";
            };
          }];
        }
      '';
      description = ''
        Settings of g3proxy.
      '';
    };
  };

  config = mkIf cfg.enable {
    #services.g3proxy.settings.log = lib.mkDefault "stdout";
    services.g3proxy.settings.log = lib.mkForce "journal";

    systemd.services.g3proxy = {
      description = "g3proxy server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart =
          let
            g3proxy-yaml = settingsFormat.generate "g3proxy.yaml" cfg.settings;
          in
          "${package}/bin/g3proxy --config-file ${g3proxy-yaml} --control-dir $RUNTIME_DIRECTORY -s -G default";

        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        ExecStop = "${package}/bin/g3proxy-ctl --control-dir $RUNTIME_DIRECTORY -G default -p $MAINPID offline";

        WorkingDirectory = "/var/lib/g3proxy";
        StateDirectory = "g3proxy";
        RuntimeDirectory = "g3proxy";
        RuntimeDirectoryPreserve = true;

        SuccessExitStatus = "SIGQUIT";
        RestartPreventExitStatus = 255;
        TimeoutStartSec = 10;
        LimitNOFILE = 10485760;
        Restart = "on-failure";
        Type = "simple";
        # Harden entirely the unit until a correct audit is performed on the code.
        DynamicUser = true;

        # RuntimeDirectoryMode = "0755";
        PrivateTmp = true;
        DevicePolicy = "closed";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        PrivateUsers = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectSystem = "strict";
        ProcSubset = "pid";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RemoveIPC = true;
        SystemCallArchitectures = "native";
        UMask = "0077";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        RestrictSUIDSGID = true;
      };
    };
  };
}
