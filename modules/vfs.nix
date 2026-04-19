# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# ANSSI R19 — Désactiver les options de montage dangereuses sur les
# systèmes de fichiers sensibles (/tmp, /var/tmp, /dev/shm).
#
# `/tmp`, `/var/tmp` et `/dev/shm` sont des vecteurs classiques
# d'exécution de binaires posés par un attaquant ayant obtenu un
# write-to-disk primitive (exploit navigateur, fichier téléchargé,
# shared memory SysV). Les options `noexec`, `nosuid`, `nodev`
# neutralisent trois des principaux vecteurs :
#
#   * `noexec`  — le kernel refuse d'exécuter un binaire depuis ce mount
#   * `nosuid`  — ignore le bit SUID/SGID (pas de privilege escalation
#                 via un binaire déposé)
#   * `nodev`   — ignore les device files (pas d'accès direct aux
#                 périphériques via une entrée fraîchement créée)
#
# Particularité NixOS : le daemon Nix (nix-daemon) utilise `/tmp` pour
# les sandbox de build, et ces sandbox exécutent des scripts de build.
# Un `/tmp` en `noexec` casserait toutes les builds. Ce module crée un
# répertoire dédié `/var/lib/nix/build` (exempté de `noexec`) et
# oriente nix-daemon dessus via `TMPDIR` + `nix.settings.build-dir`.
{ config, lib, ... }:
let
  cfg = config.securix.vfs;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    optional
    ;
in
{
  options.securix.vfs = {
    hardenTmpfs = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''

          Monte `/tmp`, `/var/tmp` et `/dev/shm` avec les options
          ANSSI R19 (`noexec,nosuid,nodev`). Default-on ; désactivable
          pour les postes de dev qui déploient des sandbox custom.
        '';
      };

      tmpSize = mkOption {
        type = types.str;
        default = "50%";
        description = "Taille allouée à `/tmp` (tmpfs).";
      };

      varTmpSize = mkOption {
        type = types.str;
        default = "25%";
        description = "Taille allouée à `/var/tmp` (tmpfs).";
      };

      tmpExec = mkOption {
        type = types.bool;
        default = false;
        description = ''

          Autorise l'exécution depuis `/tmp`. Utile uniquement si
          vous orchestrez nix-daemon (ou un autre service sensible)
          manuellement sans passer par `nixBuildTmpdir`. Défaut :
          `false` — `/tmp` est `noexec` et nix-daemon est routé vers
          `nixBuildTmpdir`.
        '';
      };

      nixBuildTmpdir = mkOption {
        type = types.path;
        default = "/var/lib/nix/build";
        description = ''

          Répertoire exécutable dédié à nix-daemon pour les sandbox
          de build. Monté sur le rootfs (pas en tmpfs pour que les
          gros builds ne remplissent pas la RAM). La sandbox Nix
          fait son propre chroot par-dessus, donc les binaires qui
          s'y exécutent ne sont pas accessibles depuis l'extérieur.
        '';
      };
    };
  };

  config = mkIf cfg.hardenTmpfs.enable {
    fileSystems."/tmp" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "size=${cfg.hardenTmpfs.tmpSize}"
        "mode=1777"
        "nosuid"
        "nodev"
      ]
      ++ optional (!cfg.hardenTmpfs.tmpExec) "noexec";
    };

    fileSystems."/var/tmp" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "size=${cfg.hardenTmpfs.varTmpSize}"
        "mode=1777"
        "noexec"
        "nosuid"
        "nodev"
      ];
    };

    fileSystems."/dev/shm" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "mode=1777"
        "noexec"
        "nosuid"
        "nodev"
      ];
    };

    # Répertoire de build dédié à nix-daemon — vit sur le rootfs pour
    # que les builds multi-Go ne fassent pas exploser tmpfs/RAM, et
    # le chemin est exec-capable (contrairement à `/tmp`).
    # `nix.settings.build-dir` est le paramètre faisant autorité
    # depuis Nix 2.21 / Lix 2.91 — le démon le lit au démarrage et
    # y route le mount `/build` de chaque sandbox.
    systemd.tmpfiles.rules = mkIf (!cfg.hardenTmpfs.tmpExec) [
      "d ${cfg.hardenTmpfs.nixBuildTmpdir} 0755 root root -"
    ];

    nix.settings.build-dir = mkIf (!cfg.hardenTmpfs.tmpExec) cfg.hardenTmpfs.nixBuildTmpdir;
  };
}
