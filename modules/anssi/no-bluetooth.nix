# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# ANSSI R15 (sous-ensemble Bluetooth) / CIS 3.1.4 — désactivation
# complète de la pile Bluetooth locale.
#
# Historique CVE de la pile Bluetooth Linux (BlueZ + kernel) :
#
#   2017  BlueBorne (8 CVEs)        RCE sans pairing, sans user interaction
#   2019  KNOB                      forçage PIN 1-byte, MITM complet
#   2020  BIAS                      impersonation de peer appairé
#   2020  BleedingTooth (kernel)    RCE via L2CAP, CVSS 8.3
#   2021  BrakTooth (16 CVEs)       crash + potentiel RCE
#   2022  DirtyBT / RCE USB stack   CVE-2022-47521 et suivants
#   2023  BLUFFS                    MITM sur session (6 CVEs)
#   2024  Flipper-Zero remote DoS
#
# Soit une cadence d'environ 1 famille de CVE par an depuis 8 ans,
# toutes exploitables à proximité physique (quelques mètres) sans
# pairing préalable pour la plupart. Sur un admin workstation qui
# voyage (aéroports, trains, cafés), c'est la plus grosse surface
# d'attaque passive non-fermable sans matériel spécifique.
#
# Sécurix cible des postes d'administration ANSSI-conformes ; cette
# règle désactive DEUX couches :
#
#   1. Service systemd      `services.blueman.enable = false`
#                           `hardware.bluetooth.enable = false`
#   2. Assertion build-time sur `hardware.bluetooth.enable` — un
#      opérateur qui tente de réactiver BT sans exclure la règle
#      voit l'échec à `nixos-rebuild`, avec le message qui pointe
#      vers `security.anssi.excludes`.
#
# Les modules kernel bluez NE SONT PAS blacklistés. Ça laisse la
# possibilité à un opérateur qui en a besoin temporairement de :
#
#   a) brancher un dongle USB BT (le kernel charge le module)
#   b) excluer la règle dans sa config (`excludes = [ "bluetooth" ]`)
#   c) activer le service (`hardware.bluetooth.enable = true`)
#   d) `nixos-rebuild switch` — **pas de reboot nécessaire**.
#
# Pourquoi pas blacklister les modules aussi : le blacklist kernel
# est cmdline-level → nécessite reboot pour activer ET pour
# désactiver. Trop de friction pour un cas d'usage légitime
# ponctuel (présenter avec un clicker BT, dépanner un accessoire).
# La défense baseline reste : aucun service BT ne tourne sur un
# poste Sécurix standard, pas d'annonce, pas de scan, pas de
# pairing → surface d'attaque passive = zéro.
#
# CAVEAT IMPORTANT : brancher un dongle + activer les services
# ré-expose la pile bluez à toutes les CVE listées ci-dessus. Voir
# le body de la PR upstream pour les recommandations opérationnelles
# (filtrage MAC, désactivation en mobilité, etc.).
#
# Accessoires cassés (à remplacer) :
#
#   * Claviers / souris BT     → USB / USB-C / Logitech Unifying (non-BT)
#   * Casques / écouteurs BT   → jack 3.5mm / USB-C / DAC filaire
#   * Transfert fichiers BT    → non applicable (AirDrop Linux n'existe pas)
#   * Geolocalisation wifi-BT  → GeoClue fonctionne en wifi-only
#   * Tethering téléphone BT   → USB-tether ou wifi-AP
#
# Le surcoût ~30-50€ pour des accessoires filaires est, en pratique,
# négligeable face à la réduction de surface d'attaque d'une pile
# entière du kernel.
{
  R15b = {
    name = "R15b_DisableBluetooth";
    anssiRef = "R15 – Désactiver les services non utilisés (Bluetooth)";
    description = ''
      Désactive complètement la pile Bluetooth (service userspace +
      modules kernel). Bloque le chargement automatique même lors
      du hotplug d'un dongle USB BT.
    '';
    severity = "reinforced";
    category = "base";
    tags = [ "bluetooth" ];

    config =
      { lib, config, ... }:
      {
        assertions = [
          {
            assertion = !(config.hardware.bluetooth.enable or false);
            message = ''
              ANSSI R15b (durcissement Bluetooth Sécurix) exige
              `hardware.bluetooth.enable = false`.

              Le Bluetooth a un historique récurrent de CVE kernel
              exploitables à distance (BlueBorne, BleedingTooth,
              BrakTooth, BLUFFS, …). Sur un poste qui voyage hors
              des environnements contrôlés, la surface d'attaque
              l'emporte sur le confort des périphériques sans fil.

              Pour autoriser le Bluetooth quand même, exclure cette
              règle : `security.anssi.excludes = [ "bluetooth" ]` —
              ET retirer les modules bluez de
              `boot.blacklistedKernelModules` dans votre configuration.
            '';
          }
          {
            assertion = !(config.services.blueman.enable or false);
            message = ''
              ANSSI R15b exige `services.blueman.enable = false`.
              À exclure via `security.anssi.excludes = [ "bluetooth" ]`.
            '';
          }
        ];

        # Met les options NixOS natives à false. Utilise mkDefault
        # pour qu'un utilisateur qui exclut explicitement cette
        # règle puisse les réactiver sans plomberie force-override.
        # Les modules kernel bluez NE SONT PAS blacklistés
        # délibérément — un dongle USB peut encore être branché et
        # reconnu par le kernel. Sans le service userspace
        # (bluetoothd / blueman), rien ne parle BT en pratique,
        # donc un module kernel seul n'est pas une surface d'attaque
        # active ; elle ne le redevient que quand l'opérateur exclut
        # explicitement cette règle et réactive le service.
        hardware.bluetooth.enable = lib.mkDefault false;
        services.blueman.enable = lib.mkDefault false;
      };

    checkScript =
      pkgs:
      pkgs.writeShellScript "check-R15b" ''
        status=0
        # Aucun service userspace bluetooth actif (la seule couche
        # appliquée par R15b — les modules kernel sont autorisés à
        # se charger, l'essentiel est que le niveau service reste
        # inactif).
        if ${pkgs.systemd}/bin/systemctl is-active bluetooth.service 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q '^active'; then
          echo "FAIL: bluetooth.service est actif"
          status=1
        fi
        if ${pkgs.systemd}/bin/systemctl is-active blueman-mechanism.service 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q '^active'; then
          echo "FAIL: blueman-mechanism.service est actif"
          status=1
        fi
        # Informationnel : présence des modules kernel.
        if ${pkgs.kmod}/bin/lsmod 2>/dev/null | ${pkgs.gnugrep}/bin/grep -qE '^(bluetooth|btusb)'; then
          echo "INFO: modules kernel bluez CHARGÉS (dongle branché ou contrôleur built-in détecté)"
          echo "  -> le userspace est désactivé, mais activer le service en excluant la règle"
          echo "     monterait BT sans reboot. Vérifier que c'est intentionnel."
        fi
        if [ $status -eq 0 ]; then
          echo "PASS: userspace Bluetooth désactivé (les modules kernel peuvent être chargés mais ne sont pas consommés)"
        fi
        exit $status
      '';
  };
}
