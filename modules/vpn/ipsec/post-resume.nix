# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# Correctif automatisé du bug suspend / resume de strongSwan / charon-nm.
#
# Quand un portable suspend avec un tunnel IPsec actif, le démon
# `charon-nm` (backend NetworkManager de strongSwan) garde les sockets
# UDP 500/4500 ouvertes mais perd tout l'état peer (IKE SAs, mappings
# NAT, SPIs). Après resume, il refuse de se réinitialiser et
# NetworkManager remonte une erreur cryptique « Cannot activate VPN
# due to missing secrets ».
#
# Le contournement Sécurix existant est une règle sudo `NOPASSWD`
# laissant les membres du groupe `operator` lancer `pkill charon-nm`
# à la main (voir networkmanager.nix, note FIXME). Ce module
# automatise la récupération via `powerManagement.resumeCommands`,
# pour que l'opérateur n'ait plus rien à faire manuellement — le
# prochain clic sur « Connect » dans NM fonctionne.
#
# La règle sudo manuelle n'est PAS retirée : elle reste un filet de
# sécurité si `powerManagement.resumeCommands` échoue pour une raison
# quelconque (erreur de script, hook systemd-sleep indisponible, …).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.securix.vpn.ipsec.resumeReconnect;
  ipsecEnabled = config.securix.vpn.ipsec.enable;
  inherit (lib) mkOption mkIf types;
in
{
  options.securix.vpn.ipsec.resumeReconnect = {
    enable = mkOption {
      type = types.bool;
      default = ipsecEnabled;
      defaultText = lib.literalExpression "config.securix.vpn.ipsec.enable";
      description = ''

        À chaque resume après suspend / hibernate, tue
        automatiquement un éventuel `charon-nm` zombie puis redémarre
        NetworkManager pour que la prochaine activation VPN réussisse
        sans intervention manuelle.

        Corrige le bug bien connu de strongSwan où `charon-nm` ne
        remarque pas que ses sockets sont devenues périmées pendant
        le suspend. Activé par défaut quand
        `securix.vpn.ipsec.enable = true`.
      '';
    };

    restartNetworkManager = mkOption {
      type = types.bool;
      default = true;
      description = ''

        Après avoir tué `charon-nm`, redémarre également NetworkManager
        pour que son état D-Bus soit synchrone avec le backend VPN
        désormais mort. À désactiver si vous pilotez NM vous-même ou
        si des units avales dépendent des redémarrages de NM.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Exécuté à chaque resume depuis suspend / hibernate / hybrid-sleep
    # via le hook systemd-sleep standard (`/lib/systemd/system-sleep/`
    # avec argument `post`).
    powerManagement.resumeCommands = ''

      # Contournement strongSwan charon-nm suspend-resume
      # (voir modules/vpn/ipsec/post-resume.nix)
      ${pkgs.procps}/bin/pkill -f charon-nm 2>/dev/null || true
      ${lib.optionalString cfg.restartNetworkManager ''

        ${pkgs.systemd}/bin/systemctl try-restart NetworkManager.service || true
      ''}
    '';
  };
}
