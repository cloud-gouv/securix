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

  manPage = pkgs.writeTextFile {
    name = "upgrade-man";
    destination = "/share/man/man1/upgrade.1";
    text = ''
      .\" SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
      .\" SPDX-License-Identifier: MIT
      .\"
      .TH UPGRADE 1 "2025" "Securix" "Commandes utilisateur"
      .
      .SH NOM
      upgrade \- mettre à jour le système NixOS depuis le dépôt d'infrastructure Securix
      .
      .SH SYNOPSIS
      .B upgrade
      .RI [\fIOPTIONS\fR]
      .I VERBE
      .
      .SH DESCRIPTION
      .B upgrade
      reconstruit et active la configuration NixOS de la machine courante à partir du
      dépôt Git d'infrastructure Securix.
      Il clone automatiquement le dépôt si celui-ci est absent, met à jour la branche
      demandée, puis délègue la reconstruction à
      .BR nixos-rebuild (8).
      .PP
      La commande doit être exécutée en tant que
      .B root
      ou via
      .BR sudo (8)
      par un membre du groupe
      .IR operator .
      Elle utilise l'agent SSH TPM2
      .RI ( /var/tmp/ssh-tpm-agent.sock )
      pour authentifier les accès au dépôt distant.
      .
      .SH VERBES
      .TP
      .B switch
      Active le nouveau système immédiatement et fait pointer le profil courant vers
      la nouvelle génération.
      .br
      .B Attention :
      cette action peut interrompre la session en cours (redémarrages de services,
      changements de PAM, etc.).
      .TP
      .B boot
      Enregistre le nouveau système dans le chargeur d'amorçage sans l'activer
      immédiatement. La nouvelle configuration sera active au prochain redémarrage.
      .TP
      .B test
      Active le nouveau système immédiatement
      .I sans
      l'ajouter au chargeur d'amorçage. Un redémarrage ultérieur restaure
      automatiquement la génération précédente. Utile pour valider une configuration
      avant de la rendre permanente.
      .TP
      .B dry-activate
      Construit le système et affiche les actions qui seraient réalisées lors d'une
      activation (redémarrages de services systemd, etc.) sans rien modifier.
      Permet de décider en connaissance de cause entre
      .B switch
      et
      .BR boot .
      .
      .SH OPTIONS
      .TP
      .BI \-\-branch " NOM"
      Branche Git à utiliser pour la reconstruction.
      Par défaut : ${config.securix.auto-updates.branch}.
      Les branches autres que la branche principale nécessitent que l'option
      .I securix.manual-upgrades.enableAnyBranch
      soit activée dans la configuration Securix, sans quoi la commande échoue.
      .TP
      .BI \-\-subdir " CHEMIN"
      Sous-répertoire du dépôt contenant la configuration NixOS à utiliser.
      Par défaut : ${
        if self.infraRepositorySubdir == "" then "<à la racine>" else self.infraRepositorySubdir
      }.
      .TP
      .B \-\-do-not-pull
      Ne pas récupérer les changements depuis le dépôt distant avant la
      reconstruction. La commande utilise l'état local du dépôt tel quel.
      Utile pour tester une branche locale non encore poussée, en combinaison
      avec
      .BR \-\-branch .
      .TP
      .BI \-\-securix\-branch " NOM"
      Branche du dépôt Securix à utiliser à la place du pin npins
      .RI ( NPINS_OVERRIDE_securix ).
      .
      .SH COMPORTEMENT DE MISE À JOUR
      .SS Branche principale
      Sur la branche principale, seul un
      .B fast-forward
      est autorisé
      .RI ( git\ pull\ \-\-ff\-only ).
      Si le fast-forward est impossible (divergence de l'historique), la commande
      échoue.
      .SS Autres branches
      Pour toute autre branche (uniquement si
      .I enableAnyBranch
      est activé), un
      .B worktree
      Git temporaire est créé dans un répertoire sécurisé, mis à jour via
      .IR "git pull \-\-rebase" ,
      puis supprimé automatiquement à la fin de l'exécution.
      .
      .SH CODES DE RETOUR
      .TP
      .B 0
      Succès.
      .TP
      .B 1
      Erreur : argument manquant ou invalide, branche non autorisée, échec Git ou
      échec de nixos-rebuild.
      .
      .SH EXEMPLES
      Activer immédiatement la dernière version de la branche principale :
      .PP
      .RS 4
      .B sudo upgrade switch
      .RE
      .PP
      Préparer la mise à jour pour le prochain redémarrage :
      .PP
      .RS 4
      .B sudo upgrade boot
      .RE
      .PP
      Tester une branche de développement sans modifier le chargeur d'amorçage :
      .PP
      .RS 4
      .B sudo upgrade \-\-branch ma-branche test
      .RE
      .PP
      Tester une branche du dépôt securix :
      .PP
      .RS 4
      .B sudo upgrade \-\-securix\-branch ma\-branche\-securix test
      .RE
      .PP
      Simuler l'activation sans rien appliquer :
      .PP
      .RS 4
      .B sudo upgrade dry-activate
      .RE
      .PP
      Reconstruire sans accès réseau (état local uniquement) :
      .PP
      .RS 4
      .B sudo upgrade \-\-do-not-pull switch
      .RE
      .
      .SH FICHIERS
      .TP
      .I /var/tmp/ssh-tpm-agent.sock
      Socket de l'agent SSH TPM2 utilisé pour l'authentification Git.
      .
      .SH CONFIGURATION NIX
      Les paramètres suivants dans la configuration NixOS contrôlent le comportement
      de cette commande :
      .TP
      .I securix.manual-upgrades.enable
      Active la commande
      .B upgrade
      et les règles sudo associées.
      .TP
      .I securix.manual-upgrades.enableAnyBranch
      Autorise l'utilisation de branches autres que la branche principale via
      .BR \-\-branch .
      Désactivé par défaut.
      .TP
      .I securix.auto-updates.branch
      Branche principale de référence.
      .TP
      .I securix.auto-updates.repoUrl
      URL du dépôt Git distant.
      .
      .SH VOIR AUSSI
      .BR nixos-rebuild (8),
      .BR git (1),
      .BR sudo (8),
      .BR systemd (1)
      .
      .SH AUTEURS
      Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>,
      Elias Coppens <elias.coppens@numerique.gouv.fr>
    '';
  };

  upgradeScript = pkgs.writeShellApplication {
    name = "upgrade";

    text = ''
      # Ensure the script runs as root
      if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root. Exiting."
        exit 1
      fi

      usage() {
        cat <<EOF
      Usage: upgrade [OPTIONS] VERBE

      Met à jour le système NixOS depuis le dépôt d'infrastructure Securix.
      Doit être exécuté en tant que root (ou via sudo pour le groupe operator).

      VERBES
        switch        Active le nouveau système immédiatement.
                      Attention : peut interrompre la session en cours.
        boot          Active le nouveau système au prochain redémarrage.
        test          Active le nouveau système maintenant sans l'ajouter au
                      chargeur d'amorçage. Un redémarrage annule les changements.
        dry-activate  Construit le système et affiche les actions qui seraient
                      réalisées sans rien appliquer.

      OPTIONS
        --branch NOM          Branche Git à utiliser
                              (défaut : ${config.securix.auto-updates.branch})
        --subdir CHEMIN       Sous-répertoire du dépôt contenant la config NixOS
                              (défaut : ${self.infraRepositorySubdir})
        --do-not-pull         Ne pas récupérer les changements distants avant de
                              reconstruire
        --securix-branch NOM  Branche du dépôt securix (surcharge du npins)
        --use-sn              Utilise le serial number pour installer la mise à
                              jour
        --help, -h            Affiche cette aide et quitte

      EXEMPLES
        sudo upgrade switch
        sudo upgrade boot
        sudo upgrade --branch mon-correctif test
        sudo upgrade --securix-branch ma-branche-securix test
        sudo upgrade --do-not-pull dry-activate
      EOF
      }

      # Default values
      BRANCH="${config.securix.auto-updates.branch}"
      REPO_PATH="${self.infraRepositoryPath}"
      SUBDIR="${self.infraRepositorySubdir}"
      REMOTE_PULL=true
      USE_SN=false
      SECURIX_BRANCH=""
      INFRA_TEMP_DIR=""
      SECURIX_OVERRIDE_TEMP_DIR=""

      # Parse arguments
      while [[ "$#" -gt 0 ]]; do
        case "$1" in
          --help|-h)
            usage
            exit 0
            ;;
          --branch)
            BRANCH="$2"
            shift 2
            ;;
          --subdir)
            SUBDIR="$2"
            shift 2
            ;;
          --do-not-pull)
            REMOTE_PULL=false
            shift 1
            ;;
          --securix-branch)
            SECURIX_BRANCH="$2"
            shift 2
            ;;
          --use-sn)
            USE_SN=true
            shift 1
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
      if [ -z "''${1:-}" ]; then
        echo "No upgrade verb provided. Available options:
        - switch: Activate the new system right now. Warning: this can break your session.
        - boot: Activate the new system on the next reboot.
        - test: Activate the new system now but doesn't add it to the bootloader. If anything goes wrong, a reboot will revert to the old version.
        - dry-activate: Perform a dry activation - builds the system and explains what the activation will cause in terms of systemd service restarts and other actions. Helps you decide whether to switch or boot."
        exit 1
      fi

      # Validate the upgrade verb against the list of accepted values.
      # Without this check, a wrong syntax such as `upgrade test my-branch` would
      # be silently accepted (the extra positional argument was ignored and the
      # upgrade proceeded on the default branch). See issue #56.
      case "$1" in
        switch|boot|test|dry-activate) ;;
        *)
          echo "Unknown upgrade verb: '$1'. Expected one of: switch, boot, test, dry-activate." >&2
          echo "Run 'upgrade --help' for usage." >&2
          exit 1
          ;;
      esac

      # Reject any trailing positional argument: options such as --branch must
      # be passed before the verb, so nothing should remain after it.
      if [ "$#" -gt 1 ]; then
        shift
        echo "Unexpected extra argument(s) after verb: $*" >&2
        echo "Options such as --branch must be passed before the verb." >&2
        echo "Run 'upgrade --help' for usage." >&2
        exit 1
      fi

      # Set the TPM2 SSH agent to retrieve the repository.
      export SSH_AUTH_SOCK=/var/tmp/ssh-tpm-agent.sock

      upgrade_cleanup() {
        local exit_code=$?
        if [ -n "$INFRA_TEMP_DIR" ]; then
          git -C "${self.infraRepositoryPath}" worktree remove "$INFRA_TEMP_DIR" || true
          rm -rf "$INFRA_TEMP_DIR"
        fi
        if [ -n "$SECURIX_OVERRIDE_TEMP_DIR" ]; then
          rm -rf "$SECURIX_OVERRIDE_TEMP_DIR"
        fi
        exit "$exit_code"
      }
      trap upgrade_cleanup EXIT

      # Check if ${self.infraRepositoryPath} exist
      if [ ! -d "${self.infraRepositoryPath}/.git" ]; then
            echo "Repository does not exist, cloning..."
            mkdir -p "${self.infraRepositoryPath}" || exit 1

            git clone "${config.securix.auto-updates.repoUrl}" "${self.infraRepositoryPath}" -b "${config.securix.auto-updates.branch}" 
      fi

      # Ensure that the origin is the right URL.
      git -C "${self.infraRepositoryPath}" remote set-url origin "${config.securix.auto-updates.repoUrl}"

      if [ "$REMOTE_PULL" = true ]; then
        git -C "${self.infraRepositoryPath}" fetch origin
        if [ "$BRANCH" == "${config.securix.auto-updates.branch}" ]; then
          # Update the repo.
          # On main branch, it's ABSOLUTELY forbidden to do anything else than --ff-only.
          git -C "${self.infraRepositoryPath}" switch "${config.securix.auto-updates.branch}"
          git -C "$REPO_PATH" pull --ff-only || exit 1
        else
          ${optionalString (
            !cfg.enableAnyBranch
          ) ''echo "Branch $BRANCH is not eligible for manual upgrade." && exit 1''}
          # Create a secure temporary directory
          INFRA_TEMP_DIR=$(mktemp -d)

          # Extract a worktree for the specified branch in the temporary directory
          git -C "${self.infraRepositoryPath}" worktree add "$INFRA_TEMP_DIR" "$BRANCH" || exit 1
          REPO_PATH="$INFRA_TEMP_DIR"

          # Update the worktree.
          # When it's not main, accept force pushes.
          git -C "$REPO_PATH" pull --rebase || exit 1
        fi
      fi

      # Important note: nixos-rebuild does not support passing --arg to nix-build
      # https://github.com/NixOS/nixpkgs/blob/nixos-25.11/pkgs/by-name/ni/nixos-rebuild-ng/src/nixos_rebuild/__init__.py
      if [ -n "$SECURIX_BRANCH" ]; then
        SECURIX_OVERRIDE_TEMP_DIR=$(mktemp -d)
        SECURIX_REPO_URL=https://github.com/cloud-gouv/securix.git
        git clone --branch "$SECURIX_BRANCH" "$SECURIX_REPO_URL" "$SECURIX_OVERRIDE_TEMP_DIR" || exit 1
        export NPINS_OVERRIDE_securix="$SECURIX_OVERRIDE_TEMP_DIR"
      fi

      TERMINAL="${self.machine.identifier}"
      # Run nixos-rebuild with the given verb
      if [ "$USE_SN" = true ]; then
          TERMINAL=$(${pkgs.dmidecode}/bin/dmidecode -s system-serial-number 2>/dev/null || echo "unknown")

          if [ "$TERMINAL" = "unknown" ]; then
            echo "No serial number found for this system, aborting upgrade." 
            exit 1
          fi
      fi

      nixos-rebuild "$1" --file "$REPO_PATH/$SUBDIR" --attr terminals."$TERMINAL".system
    '';
  };
in
{
  options.securix.manual-upgrades = {
    enable = mkEnableOption "manual upgrade script";
    enableAnyBranch = mkEnableOption "any branch to be targetted";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      upgradeScript
      manPage
    ];
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
