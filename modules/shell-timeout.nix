# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# ANSSI R36 / CIS 5.7 — Déconnexion automatique des sessions inactives.
#
# Sécurix verrouille déjà l'écran graphique via swaylock après
# 5 minutes (swayidle + swaylock), mais les sessions SHELL (TTY, SSH,
# terminal graphique) restent ouvertes indéfiniment. Un opérateur qui
# part en pause avec un shell SSH bastion ouvert expose cette session
# à qui accède ensuite au poste.
#
# Ce module pose la variable `TMOUT` (bash/zsh) en `readonly`, ce qui
# fait sortir automatiquement un shell interactif après N secondes
# d'inactivité. `readonly` empêche l'utilisateur de la redéfinir dans
# son `~/.bashrc`.
#
# Limitations (documentées honnêtement) :
#
#   * N'affecte que les shells interactifs bash/zsh (pas dash/fish —
#     ksh l'ignore aussi),
#   * Ne compte pas l'activité à l'intérieur d'un long-running
#     process (ex. `vim`, `less`, `watch`) — seule la lecture d'une
#     prompt compte,
#   * tmux / screen continuent de tourner (attachent à un serveur
#     dédié, pas au shell) — contourne TMOUT pour qui sait.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.securix.shell.timeout;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    concatStringsSep
    ;
in
{
  options.securix.shell.timeout = {
    enable = mkEnableOption ''

      la déconnexion automatique des shells interactifs bash / zsh
      inactifs via la variable d'environnement `TMOUT`
    '';

    seconds = mkOption {
      type = types.ints.positive;
      default = 900; # 15 minutes
      description = ''

        Délai d'inactivité avant que le shell ne sorte. Ne s'applique
        qu'aux sessions de login interactives bash / zsh. 900 s
        (15 min) est le défaut recommandé par CIS pour les postes
        d'administration ; des délais plus longs affaiblissent le
        contrôle.
      '';
      example = 600;
    };

    excludedUsers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''

        Utilisateurs pour lesquels `TMOUT` n'est PAS fixé. À utiliser
        avec parcimonie — chaque exemption rouvre le risque de
        session inactive pour ce compte. Cas typiques légitimes :
        comptes de service dédiés qui font tourner de la maintenance
        interactive longue, jamais des opérateurs admin.
      '';
      example = [ "long-running-bot" ];
    };
  };

  config = mkIf cfg.enable {
    environment.etc."profile.d/securix-tmout.sh" = {
      text = ''

        # SPDX généré — module securix.shell.timeout
        # ANSSI R36 / CIS 5.7 — déconnexion auto des shells inactifs.
        ${
          if cfg.excludedUsers == [ ] then
            ''

              TMOUT=${toString cfg.seconds}
              readonly TMOUT
              export TMOUT
            ''
          else
            ''

              case ":${concatStringsSep ":" cfg.excludedUsers}:" in
                *":$(${pkgs.coreutils}/bin/id -un):"*)
                  # Utilisateur exempté du timeout shell.
                  ;;
                *)
                  TMOUT=${toString cfg.seconds}
                  readonly TMOUT
                  export TMOUT
                  ;;
              esac
            ''
        }
      '';
      mode = "0644";
    };
  };
}
