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

    repoSubdir = mkOption {
      type = types.str;
      default = "securix";
      description = "Sous-répertoire de la souche Sécurix";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.system-infrastructure-sync = {
      description = "Synchronization of the system infrastructure repository";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [
        pkgs.networkmanager
        pkgs.git
        pkgs.openssh
        pkgs.util-linux
        pkgs.gawk
        pkgs.libnotify
        pkgs.sudo
      ];
      script = ''
        _notify_current_user() {
            local title="$1"
            local message="$2"

            # Get all active sessions with a valid user
            mapfile -t sessions < <(loginctl list-sessions --no-legend | awk '{print $1, $2, $3}' | grep -v '^ ')

            # Check if there are active sessions
            if [[ ''${#sessions[@]} -eq 0 ]]; then
                echo "No active sessions found." >&2
                return 1
            fi

            for session in "''${sessions[@]}"; do
                # Extract session details: ID, user, and display
                local session_id user display
                session_id=$(echo "$session" | awk '{print $1}')
                uid=$(echo "$session" | awk '{print $2}')
                user=$(echo "$session" | awk '{print $3}')

                # Notify each user/session
                if [[ -n "$user" ]]; then
                    # Graphical notification for GUI sessions
                    sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
                        notify-send "$title" "$message"
                else
                    # Terminal notification for non-GUI sessions
                    sudo -u "$user" echo "$title: $message" | wall
                fi
            done
          }

          nm-online -q --timeout=30 || { echo "No Internet, skipping synchronization..."; exit 100; }
          if ssh-add -L &>/dev/null; then
              echo "SSH identities are loaded:"
              ssh-add -L
          else
              echo "No system SSH identities loaded, is the TPM2 broken or the onboarding was insufficient?"
              exit 101
          fi
          export GIT_SSHCOMMAND="ssh -i /etc/ssh/ssh_tpm_host_ecdsa_key.tpm"
          if [ -d "$REPO_DIR/.git" ]; then
            echo "Repository exists, pulling latest changes..."
            cd "$REPO_DIR/$REPO_SUBDIR" || exit 1

            UPSTREAM=''${1:-'@{u}'}
            LOCAL=$(git rev-parse @)
            REMOTE=$(git rev-parse "$UPSTREAM")
            BASE=$(git merge-base @ "$UPSTREAM")

            if [ $LOCAL = $REMOTE ]; then
                echo "Up-to-date. Skipping."
                exit 0
            elif [ $LOCAL = $BASE ]; then
                _notify_current_user "[Sécurix] Mises à jour" "Une mise à jour est disponible du système et sera téléchargé."
            elif [ $REMOTE = $BASE ]; then
                _notify_current_user "[Sécurix] Mises à jour" "Votre système diverge du dépot de code à cause de changements locaux."
                exit 102
            else
                _notify_current_user "[Sécurix] Mises à jour" "Votre système diverge du dépot de code et ne peut etre synchronisé automatiquement."
                exit 103
            fi

            git pull || exit 1

            _notify_current_user "[Sécurix] Mises à jour" "Le code de votre système a été mis à jour. La reconstruction de votre système en arrière plan va commencer."
            nixos-rebuild boot --attr terminals."${config.securix.self.identifier}".system
            _notify_current_user "[Sécurix] Mises à jour" "La reconstruction du système est complète, au prochain redémarrage, votre système sera mis à jour."
          else
            echo "Repository does not exist, cloning..."
            _notify_current_user "[Sécurix] Mises à jour" "Initialisation du code d'infrastructure..."
            git clone "$REPO_URL" "$REPO_DIR" || _notify_current_user "[Sécurix] Mises à jour" "Initialisation échoué; est-ce que votre TPM2 est correctement onboardé?" && _notify_current_user "[Sécurix] Mises à jour" "Initialisation réussie. Reconstruction du système..."
            nixos-rebuild boot --attr terminals."${config.securix.self.identifier}".system
            _notify_current_user "[Sécurix] Mises à jour" "La reconstruction du système est complète, au prochain redémarrage, votre système sera mis à jour."
          fi
      '';
      serviceConfig = {
        Restart = "on-failure";
        RestartPreventExitStatus = [
          100
          101
          102
        ];
        Environment = [
          "SSH_AUTH_SOCK=/var/tmp/ssh-tpm-agent.sock"
          "REPO_DIR=${config.securix.self.infraRepositoryPath}"
          "REPO_URL=${cfg.repoUrl}"
          "REPO_SUBDIR=${cfg.repoSubdir}"
        ];
      };
    };

    systemd.timers.system-infrastructure-sync = {
      description = "Timer for synchronization of the system infrastructure repository";
      timerConfig = {
        OnBootSec = "10m"; # Delay before the first execution (10 minutes after boot)
        OnUnitActiveSec = "1h"; # Set the interval to 1 hour (adjust as needed)
        Persistent = true;
      };
      wantedBy = [ "timer.target" ];
    };
  };
}
