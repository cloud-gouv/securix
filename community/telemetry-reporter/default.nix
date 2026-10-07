# SPDX-FileCopyrightText: 2026 Pauline Legrand <pauline.legrand@numerique.gouv.fr>
# SPDX-FileContributor: 2026 Fabien VANEENOO <fabien.vaneenoo.ext@numerique.gouv.fr>
# SPDX-FileContributor: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>
# SPDX-FileContributor: 2026 Xavier Maso <xavier.maso.ext@numerique.gouv.fr>
# SPDX-FileContributor: 2026 Lucas Desgouilles <lucas.desgouilles@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.securix.telemetry-reporter;

  script = pkgs.writeShellApplication {
    name = "securix-telemetry-report";

    runtimeInputs = with pkgs; [
      acpi
      coreutils
      curl
      dmidecode
      getent
      jq
      nixos-rebuild
      sbctl
      util-linux
    ];

    text = builtins.readFile ./securix-telemetry-reporter.sh;
  };
in
{
  options.securix.telemetry-reporter = {
    enable = lib.mkEnableOption "Basic telemetry reporting for Sécurix";

    gristUrl = lib.mkOption { type = lib.types.str; };

    docId = lib.mkOption { type = lib.types.str; };

    tableId = lib.mkOption { type = lib.types.str; };

    useProxy = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    frequency = lib.mkOption {
      type = lib.types.str;
      description = ''
        The frequency at which to send reports. See systemd.time(7) for more information on the syntax.
      '';
      default = "daily";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.securix-telemetry-reporter = {
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      environment = lib.mkMerge [
        { GRIST_URL = "${cfg.gristUrl}/o/docs/api/s/${cfg.docId}/tables/${cfg.tableId}/records"; }
        (lib.mkIf cfg.useProxy {
          http_proxy = config.networking.proxy.default;
          https_proxy = config.networking.proxy.default;
          all_proxy = config.networking.proxy.default;
          no_proxy = lib.concatStringsSep "," config.securix.http-proxy.exceptions;
        })
      ];

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe script;
        Restart = "on-failure";
        RestartSec = 60;
        StartLimitBurst = 10;
        StartLimitIntervalSec = 300;
      };
    };

    systemd.timers.securix-telemetry-reporter = {
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = cfg.frequency;
        Unit = "securix-telemetry-reporter.service";
      };
    };
  };
}
