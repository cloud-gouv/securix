# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: Elias Coppens <elias.coppens@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkIf mkEnableOption optionalString;
  self = config.securix.self;
  cfg = config.securix.manual-upgrades;
  upgradeScript = pkgs.writeShellApplication {
    name = "upgrade";

    text = ''
      # Ensure the script runs as root
      if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root. Exiting."
        exit 1
      fi

      # Default values
      BRANCH="main"
      SUBDIR="${self.infraRepositorySubdir}"

      # Parse arguments
      while [[ "$#" -gt 0 ]]; do
        case "$1" in
          --branch)
            BRANCH="$2"
            shift 2
            ;;
          --subdir)
            SUBDIR="$2"
            shift 2
            ;;
          --)
            shift
            break
            ;;
          *)
            break
            ;;
        esac
      done

      # Ensure an upgrade verb is provided
      if [ -z "$1" ]; then
        echo "No upgrade verb provided. Available options:
        - switch: Activate the new system right now. Warning: this can break your session.
        - boot: Activate the new system on the next reboot.
        - test: Activate the new system now but doesn't add it to the bootloader. If anything goes wrong, a reboot will revert to the old version.
        - dry-activate: Perform a dry activation - builds the system and explains what the activation will cause in terms of systemd service restarts and other actions. Helps you decide whether to switch or boot."
        exit 1
      fi

      # Remove all HTTP proxies
      unset all_proxy http_proxy https_proxy no_proxy
      # Set the TPM2 SSH agent to retrieve the repository.
      export SSH_AUTH_SOCK=/var/tmp/ssh-tpm-agent.sock

      # Ensure that the origin is the right URL.
      git -C "${self.infraRepositoryPath}" remote set-url origin "${config.securix.auto-updates.repoUrl}"
      git -C "${self.infraRepositoryPath}" fetch origin

      if [ "$BRANCH" == "main" ]; then
        REPO_PATH="${self.infraRepositoryPath}"

        # Update the repo.
        # On main, it's ABSOLUTELY forbidden to do anything else than --ff-only.
        git -C "$REPO_PATH" pull --ff-only || exit 1
      else
        ${
          optionalString (
            !cfg.enableAnyBranch
          ) ''echo "Branch $BRANCH is not eligible for manual upgrade." && exit 1''
        }
        # Create a secure temporary directory
        TEMP_DIR=$(mktemp -d)
        trap 'git -C "${self.infraRepositoryPath}" worktree remove "$TEMP_DIR"; rm -rf "$TEMP_DIR"' EXIT
        
        # Extract a worktree for the specified branch in the temporary directory
        git -C "${self.infraRepositoryPath}" worktree add "$TEMP_DIR" "$BRANCH" || exit 1
        REPO_PATH="$TEMP_DIR"

        # Update the worktree.
        # When it's not main, accept force pushes.
        git -C "$REPO_PATH" pull --rebase || exit 1
      fi

      # Run nixos-rebuild with the given verb
      nixos-rebuild "$1" --file "$REPO_PATH/$SUBDIR" --attr terminals."${self.identifier}".system
    '';
  };
in
{
  options.securix.manual-upgrades = {
    enable = mkEnableOption "manual upgrade script";
    enableAnyBranch = mkEnableOption "any branch to be targetted";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ upgradeScript ];
    security.sudo = {
      enable = true;
      extraRules = [
        {
          groups = [ "operator" ];
          commands = [
            {
              command = "${upgradeScript}/bin/upgrade";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/upgrade";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };
  };
}
