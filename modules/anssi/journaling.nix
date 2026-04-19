# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# Règles ANSSI de journalisation pour systemd-journald.
#
# R31 force le journal à persister entre les redémarrages et applique
# des bornes raisonnables de rétention / taille pour qu'un service en
# emballement ne puisse pas saturer le disque et faire évincer des
# preuves forensiques. Complément du module auditd (qui couvre la piste
# des événements de sécurité) ; R31 concerne le journal système
# générique.
#
# Note : le défaut NixOS `services.journald.storage = "auto"` fait que
# le journal n'est persistant que si `/var/log/journal` existe déjà.
# En le forçant à `"persistent"`, le répertoire est créé de manière
# déterministe au moment de l'activation.
let
  mkSysctlChecker = _: _: ""; # inutilisé ici mais conserve la symétrie avec les autres fichiers de règles
in
{
  R31 = {
    name = "R31_PersistentJournal";
    anssiRef = "R31 – Journaliser les événements système de façon persistante";
    description = ''
      Garantit que systemd-journald stocke ses logs de manière
      persistante avec une taille et une rétention bornées, pour que
      les redémarrages n'effacent pas les preuves forensiques et qu'une
      source de log en emballement ne puisse pas épuiser l'espace disque.
    '';
    severity = "intermediary";
    category = "base";

    config = _: {
      services.journald = {
        # Force le stockage persistant (défaut NixOS = "auto" qui ne
        # persiste que si /var/log/journal existe déjà).
        storage = "persistent";

        extraConfig = ''
          # --- Bornes R31 taille ---
          # Note : SystemMaxUse est réglé séparément par modules/journal.nix ;
          # on évite délibérément la duplication ici pour ne pas créer de
          # surprises d'ordre de dernière écriture. Les bornes ci-dessous
          # sont orthogonales.
          SystemKeepFree=500M
          SystemMaxFileSize=100M
          SystemMaxFiles=100
          RuntimeMaxUse=128M

          # --- Rétention R31 ---
          # Garder au plus 90 jours de logs.
          MaxRetentionSec=90day

          # --- Intégrité (FSS sealing) ---
          # Seal=yes est le défaut NixOS mais réaffirmé ici pour la clarté.
          Seal=yes
          Compress=yes

          # --- Forwarding désactivé par défaut (R31) ---
          # Les utilisateurs qui souhaitent un forwarding distant doivent
          # passer explicitement par services.journald.upload.*.
          ForwardToSyslog=no
        '';
      };
    };

    checkScript =
      pkgs:
      pkgs.writeShellScript "check-R31" ''
        # Vérification de la persistance R31
        if [ ! -d /var/log/journal ]; then
          echo "FAIL: /var/log/journal n'existe pas — le journal est volatile."
          exit 1
        fi

        # Bornes R31 — vérifie au moins que SystemMaxUse soit défini
        if ! ${pkgs.systemd}/bin/journalctl --disk-usage >/dev/null 2>&1; then
          echo "FAIL: journalctl indisponible ou journal illisible."
          exit 1
        fi

        # Vérifie que la config journald contient des bornes (toute valeur acceptée)
        for key in SystemMaxUse SystemKeepFree SystemMaxFileSize MaxRetentionSec; do
          if ! ${pkgs.gnugrep}/bin/grep -q "^''${key}=" /etc/systemd/journald.conf; then
            echo "FAIL: journald.conf sans directive ''${key}="
            exit 1
          fi
        done

        echo "PASS: R31 journal persistant + rétention OK"
      '';
  };
}
