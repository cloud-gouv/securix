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

  commands = lib.concatMapAttrsStringSep "\n\n" (
    field: command: if command != null then "fields[${field}]=$(${command})" else ""
  ) cfg.fields;

  script = pkgs.writeShellApplication {
    name = "securix-telemetry-report";

    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
      nixos-rebuild
    ];

    text = builtins.replaceStrings [ "#COMMANDS#" ] [ commands ] (
      builtins.readFile ./securix-telemetry-reporter.sh
    );
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

    fields = lib.mkOption { type = with lib.types; attrsOf (nullOr str); };
  };

  config = lib.mkIf cfg.enable {
    securix.telemetry-reporter.fields = lib.mapAttrs (_: lib.mkDefault) {
      currentDate = "date -Iseconds";

      user = "${pkgs.getent}/bin/getent group video | cut -d ':' -f 4";
      hostName = "${pkgs.hostname}/bin/hostname";

      chassisSerial = "${pkgs.dmidecode}/bin/dmidecode --string chassis-serial-number || ${pkgs.dmidecode}/bin/dmidecode --string system-serial-number";
      chassisFamily = "${pkgs.dmidecode}/bin/dmidecode --string system-family || ${pkgs.dmidecode}/bin/dmidecode --string system-version";

      energyCapacity = "${pkgs.acpi}/bin/acpi --battery --details | grep 'Battery 0:' | tail -n 1";

      displayResolution = "cat /sys/class/drm/card*-eDP-*/modes | sort --numeric-sort --reverse | uniq | head -n 1";

      nixosBuildDate = "jq -r '.date' <<< \"$current_gen\"";
      nixosVersion = "jq -r '.nixosVersion' <<< \"$current_gen\"";
      kernelVersion = "jq -r '.kernelVersion' <<< \"$current_gen\"";
      currentGeneration = "jq -r '.generation' <<< \"$current_gen\"";

      generationCount = "nixos-rebuild list-generations --json | jq 'length'";

      bootTime = "systemctl show -p KernelTimestamp --value";

      rootfsCapacity = "df -h --output=size / | tail -n+2";
      rootfsUse = "df -h --output=used,pcent / | tail -n+2";
      espCapacity = "df -h --output=size /boot | tail -n+2";
      espUse = "df -h --output=used,pcent /boot | tail -n+2";

      secureBoot = ''
         ${pkgs.sbctl}/bin/sbctl status --json | jq -r '
          if .secure_boot and .installed and (.setup_mode | not) then
            "OK"
          else
            del(.guid, .firmware_quirks) | @json | gsub("[\"{}]"; "")
          end
        '
      '';
    };

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
