# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.securix.auto-updates;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
{
  options.securix.auto-updates = {
    enable = mkEnableOption "la mise à jour automatique du code d'infrastructure de Sécurix";
    enableRebuild = mkEnableOption "la reconstruction automatique du système";

    repoUrl = mkOption {
      type = types.str;
      description = "URL de clonage du repo d'infrastructure Sécurix";
    };

    branch = mkOption {
      type = types.str;
      default = "main";
      description = "Branche du dépôt d'infrastructure Sécurix à mettre à jour";
    };

    repoSubdir = mkOption {
      type = types.str;
      default = "securix";
      description = "Sous-répertoire de la souche Sécurix";
    };
    maxGenerationsToKeep = mkOption {
      type = types.int;
      default = 30;
      description = "Nombre des dernières générations à préserver";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.system-infrastructure-sync = {
      description = "Synchronization of the system infrastructure repository";
      # The upgrade must always retry, even after many consecutive failures
      # (e.g. no network, TPM2 not ready). Disabling the start rate limit
      # prevents systemd from leaving the unit in a permanent failed state
      # once StartLimitBurst is reached. The exponential backoff below keeps
      # the retry rate bounded instead.
      startLimitIntervalSec = 0;
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [
        pkgs.networkmanager
        pkgs.git
        pkgs.openssh
        pkgs.util-linux
        pkgs.gawk
        # The fallback path. Keep it until the hints replace the notifications.
        pkgs.libnotify
        pkgs.sudo
        pkgs.nixos-rebuild
        config.nix.package
        config.securix.hints.package
      ];
      script = ''
        _notify_current_user() {
          local title="$1"
          local message="$2"

          mapfile -t sessions < <(loginctl list-sessions --no-legend | awk '{print $1, $2, $3}' | grep -v '^ ')

          if [[ ''${#sessions[@]} -eq 0 ]]; then
              echo "No active sessions found." >&2
              return 1
          fi

          for session in "''${sessions[@]}"; do
              local uid user
              uid=$(echo "$session" | awk '{print $2}')
              user=$(echo "$session" | awk '{print $3}')

              if [[ -n "$user" ]]; then
                  sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
                      notify-send "$title" "$message" || true
              else
                  echo "$title: $message" | wall
              fi
          done
        }

        _hint_set() {
          local key="$1"
          local kind="$2"
          local severity="$3"
          local title="$4"
          local body="$5"
          shift 5

          securix-hintctl set \
            --source securix-auto-updates \
            --key "$key" \
            --kind "$kind" \
            --severity "$severity" \
            --title "$title" \
            --body "$body" \
            "$@" || _notify_current_user "$title" "$body" || true
        }


        _hint_clear() {
          securix-hintctl clear securix-auto-updates "$1" || true
        }

        nm-online -q --timeout=30 || { echo "No Internet, skipping synchronization..."; exit 100; }
        if ssh-add -L &>/dev/null; then
            echo "SSH identities are loaded:"
            ssh-add -L
        else
            echo "No system SSH identities loaded, is the TPM2 broken or the onboarding was insufficient?"
            _hint_set onboarding-failed security 3 \
              "Initialisation échouée" \
              "L'initialisation a échoué. Vérifiez que le TPM2 est correctement onboardé."
            exit 101
        fi
        if [ -d "$REPO_DIR/.git" ]; then
          echo "Repository exists, pulling latest changes..."
          cd "$REPO_DIR/$REPO_SUBDIR" || exit 1

          git remote set-url origin "${cfg.repoUrl}"
          git fetch origin || exit 1
          git branch --set-upstream-to="origin/${cfg.branch}" "${cfg.branch}"

          UPSTREAM='${cfg.branch}@{u}'
          LOCAL=$(git rev-parse @)
          REMOTE=$(git rev-parse "$UPSTREAM")
          BASE=$(git merge-base @ "$UPSTREAM")

          if [ $LOCAL = $REMOTE ]; then
              echo "Up-to-date. Skipping."
              _hint_clear update-available
              _hint_clear rebuilding
              exit 0
          elif [ $LOCAL = $BASE ]; then
              _hint_set update-available maintenance 1 \
                "Mises à jour" \
                "Une mise à jour du système est disponible et sera téléchargée."
          elif [ $REMOTE = $BASE ]; then
              _hint_set diverged-local maintenance 2 \
                "Divergence locale" \
                "Votre système diverge du dépôt à cause de changements locaux."
              exit 102
          else
              _hint_set diverged-remote maintenance 2 \
                "Divergence distante" \
                "Votre système diverge du dépôt et ne peut pas être synchronisé automatiquement."
              exit 103
          fi

          git pull || exit 1

          _hint_set rebuilding maintenance 1 \
            "Reconstruction" \
            "Le code du système a été mis à jour. La reconstruction en arrière-plan commence."
        else
          echo "Repository does not exist, cloning..."
          mkdir -p "$REPO_DIR" || exit 1

          git clone "$REPO_URL" "$REPO_DIR" -b "${cfg.branch}" || {
            _hint_set onboarding-failed security 3 \
              "Initialisation échouée" \
              "L'initialisation a échoué. Vérifiez que le TPM2 est correctement onboardé."
            exit 1
          }

          cd "$REPO_DIR/$REPO_SUBDIR" || exit 1
        fi

        # use narinfo-cache-positive-ttl option to 0 forces a revalidation on each rebuild because when renewing the cache signing key, 
        # the substitution was not made because the narinfo entry has a TTL of 30 days and is not invalidated. 
        # (https://git.lix.systems/lix-project/lix/issues/1268 and https://git.lix.systems/lix-project/lix/issues/1269)

        nixos-rebuild boot --attr terminals."${config.securix.self.machine.identifier}".system --option narinfo-cache-positive-ttl 0
        nix-env -p /nix/var/nix/profiles/system --delete-generations +${toString cfg.maxGenerationsToKeep}
        nix-store --gc --max-freed 10G

        _hint_clear rebuilding
        _hint_clear onboarding-failed
        _hint_clear reboot
      '';
      serviceConfig = {
        Restart = "on-failure";
        # Exponential backoff: RestartSec * 2^n, capped at restartMaxDelay.
        RestartSec = "1min";
        RestartSteps = 8;
        RestartMaxDelaySec = "4h";
        RuntimeMaxSec = "2h";
        Environment = [
          "SSH_AUTH_SOCK=/var/tmp/ssh-tpm-agent.sock"
          "REPO_DIR=${config.securix.self.machine.infraRepositoryPath}"
          "REPO_URL=${cfg.repoUrl}"
          "REPO_SUBDIR=${cfg.repoSubdir}"
        ];
      };
    };

    systemd.timers.system-infrastructure-sync = {
      description = "Timer for synchronization of the system infrastructure repository";
      timerConfig = {
        OnBootSec = "10m"; # Delay before the first execution (10 minutes after boot)
        # Base the hourly check on inactivity rather than activity: after a
        # long backoff sequence the OnUnitActiveSec deadline may already have
        # elapsed, which would immediately re-trigger the unit on success.
        OnUnitInactiveSec = "1h";
      };
      wantedBy = [ "timers.target" ];
    };
  };
}
