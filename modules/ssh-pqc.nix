# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# Posture SSH post-quantique — enforcement du KEX.
#
# OpenSSH 9.9+ livre deux algorithmes de KEX hybrides post-quantiques :
#   * mlkem768x25519-sha256          (NIST FIPS 203, préféré)
#   * sntrup761x25519-sha512         (prédécesseur CRYSTALS, largement déployé)
#
# Le défaut nixpkgs de `KexAlgorithms` publie déjà ces derniers EN
# PREMIER, mais garde curve25519 et DH-group-exchange classiques en
# fallback pour que les connexions vers des peers legacy réussissent.
# Ce fallback signifie que si un attaquant actif peut faire échouer la
# négociation PQ (dropper des paquets, modifier KEX_INIT), la session
# retombe silencieusement sur un groupe classique — la clé de session
# résultante n'est *pas* PQ-safe et un adversaire
# `harvest-now-decrypt-later` pourrait la dériver depuis le handshake
# capturé.
#
# Ce module offre un toggle strict-mode qui retire le fallback
# classique, pour que *toute* session SSH terminée sur cette machine
# utilise un handshake PQ hybride ou échoue fermée au handshake.
#
# Note (2026) : OpenSSH n'a pas de support upstream pour les
# *signatures* post-quantiques (ML-DSA / SLH-DSA). Les host keys et
# user keys restent Ed25519 / ECDSA / RSA — vulnérables à une attaque
# future `store-now-forge-later`. Voir docs/ssh-pqc-posture.md pour
# le modèle de menace complet et les mitigations recommandées
# (rotation fréquente, veille upstream).
{ config, lib, ... }:
let
  cfg = config.securix.ssh.pqc;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    concatStringsSep
    ;
in
{
  options.securix.ssh.pqc = {
    enforceKex = mkEnableOption ''

      l'échange de clés strictement post-quantique pour sshd.

      Quand activé, le fallback classique (`curve25519-sha256`,
      DH group-exchange) est retiré de `KexAlgorithms` — tout peer
      qui ne parle pas un KEX hybride PQ est rejeté au handshake.

      Désactivé par défaut : activer casse les connexions vers les
      serveurs SSH legacy (< OpenSSH 9.0) et les anciens clients. À
      n'activer que lorsque chaque peer qui compte fait tourner
      OpenSSH 9.9+ ou une implémentation PQ-capable équivalente
    '';

    algorithms = mkOption {
      type = types.listOf types.str;
      default = [
        "mlkem768x25519-sha256"
        "sntrup761x25519-sha512"
        "sntrup761x25519-sha512@openssh.com"
      ];
      description = ''

        Algorithmes KEX autorisés quand `enforceKex = true`. L'ordre
        compte : OpenSSH prend la première entrée mutuellement
        supportée. Toutes les entrées doivent être des hybrides PQ —
        ajouter une courbe classique ici annule l'intérêt du
        enforcement.
      '';
    };
  };

  config = mkIf cfg.enforceKex {
    services.openssh.settings = {
      KexAlgorithms = cfg.algorithms;

      # Si un KEX strict est imposé, on épingle `HostKeyAlgorithms` et
      # `PubkeyAcceptedAlgorithms` sur le sous-ensemble moderne pour
      # que l'opérateur ne puisse pas négocier accidentellement
      # `ssh-rsa-sha1` ou `ssh-dss`. Ces derniers sont déjà désactivés
      # dans les défauts récents d'OpenSSH, mais l'épinglage rend la
      # politique explicite dans `sshd_config` (audit +
      # reproductibilité).
      # `HostKeyAlgorithms` / `PubkeyAcceptedAlgorithms` sont des
      # options atomiques (chaîne unique avec virgules), pas des
      # listes — contrairement à `KexAlgorithms`.
      HostKeyAlgorithms = concatStringsSep "," [
        "ssh-ed25519"
        "ssh-ed25519-cert-v01@openssh.com"
        "ecdsa-sha2-nistp256"
        "ecdsa-sha2-nistp256-cert-v01@openssh.com"
        "rsa-sha2-512"
        "rsa-sha2-512-cert-v01@openssh.com"
      ];

      PubkeyAcceptedAlgorithms = concatStringsSep "," [
        "ssh-ed25519"
        "ssh-ed25519-cert-v01@openssh.com"
        "ecdsa-sha2-nistp256"
        "ecdsa-sha2-nistp256-cert-v01@openssh.com"
        "ecdsa-sha2-nistp384"
        "ecdsa-sha2-nistp521"
        "rsa-sha2-512"
        "rsa-sha2-512-cert-v01@openssh.com"
      ];
    };
  };
}
