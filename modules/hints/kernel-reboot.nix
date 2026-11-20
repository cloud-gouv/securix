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
  inherit (lib) getExe mkIf;

  script = pkgs.writeShellApplication {
    name = "securix-hints-kernel-reboot";
    runtimeInputs = [
      pkgs.coreutils
      cfg.package
    ];
    text = ''
      set -eu

      profile=/nix/var/nix/profiles/system
      source=${cfg.criticalSource}
      key=reboot

      clear_hint() {
        securix-hintctl clear "$source" "$key" || true
      }

      running="''${SECURIX_HINTS_RUNNING_KERNEL:-$(uname -r)}"

      target="''${SECURIX_HINTS_TARGET_KERNEL:-}"
      if [ -z "$target" ]; then
        if [ ! -e "$profile/kernel" ]; then
          clear_hint
          exit 0
        fi
        target="$(readlink -f "$profile/kernel" || true)"
      fi

      if [ -z "$target" ]; then
        clear_hint
        exit 0
      fi

      # /nix/store/<hash>-linux-<release>/bzImage
      base="$(basename "$(dirname "$target")")"
      wanted="''${base#*-linux-}"

      if [ "$wanted" = "$base" ]; then
        clear_hint
        exit 0
      fi

      if [ "$wanted" = "$running" ]; then
        clear_hint
        exit 0
      fi

      uptime="''${SECURIX_HINTS_UPTIME_SECONDS:-$(cut -d. -f1 /proc/uptime)}"
      days=$(( uptime / 86400 ))

      if [ "$days" -lt 1 ]; then
        clear_hint
        exit 0
      fi

      if [ "$days" -ge 6 ]; then
        severity=3
      elif [ "$days" -ge 3 ]; then
        severity=2
      else
        severity=1
      fi

      hint() {
        securix-hintctl set \
          --source "$source" \
          --key "$key" \
          --kind reboot \
          --severity "$severity" \
          --title "Redémarrage requis" \
          --body "Le noyau $running est en cours. Le noyau $wanted attend un redémarrage, et le système tourne depuis $days jour(s)." \
          "$@" || true
      }

      if [ "$severity" -ge 3 ]; then
        hint --action "reboot:Redémarrer maintenant:primary"
      else
        hint \
          --action "reboot:Redémarrer maintenant:primary" \
          --action "snooze:Plus tard"
      fi
    '';
  };
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = [ script ];

    systemd.services.securix-hints-kernel-reboot = {
      description = "Propose a reboot when a new kernel waits";
      after = [ "securix-hintd.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = getExe script;
      };
    };

    systemd.timers.securix-hints-kernel-reboot = {
      description = "Look for a kernel that waits for a reboot";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "15min";
        OnUnitActiveSec = "6h";
        Unit = "securix-hints-kernel-reboot.service";
      };
    };
  };
}
