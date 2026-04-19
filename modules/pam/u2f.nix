# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    concatStringsSep
    concatMapStringsSep
    mapAttrsToList
    ;
  cfg = config.securix.pam.u2f;
in
{
  options.securix.pam.u2f = {
    enable = mkEnableOption "l'utilisation de U2F pour se connecter aux comptes locaux";
    appId = mkOption {
      type = types.str;
      default = "pam://$HOSTNAME";
      description = "Identifiant d'application des clés à détecter pour ce système";
      example = "pam://acme-corp-workstations";
    };
    origin = mkOption {
      type = types.str;
      default = "pam://$HOSTNAME";
      description = "Identifiant d'origine des clés à détecter pour ce système";
      example = "pam://acme-corp-workstations";
    };
    keys = mkOption {
      type = types.attrsOf (types.listOf types.str);
      description = "Ensemble attributaire de comptes et de leurs clés associées";
    };

    lockOnRemoval = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = ''
          Verrouille toutes les sessions graphiques (via `loginctl lock-sessions`)
          dès qu'une clé de sécurité FIDO2 reconnue est déconnectée du port USB.

          Met en œuvre le modèle « présence physique = présence de session »
          recommandé par l'ANSSI pour les postes d'administration : retirer
          la clé doit révoquer la session logique, pas juste suspendre
          l'authentification.
        '';
      };

      vendorIds = mkOption {
        type = types.listOf types.str;
        default = [ "1050" ]; # Yubico
        description = ''
          Liste des vendor IDs USB (4 caractères hex, minuscules) dont
          l'événement de déconnexion doit déclencher le verrouillage.
          Fournisseurs FIDO2 courants :

            - 1050 : Yubico (YubiKey 4/5, Security Key, Bio)
            - 0483 : SoloKeys (Solo, Somu)
            - 1209 : SoloKeys v2 et OnlyKey
            - 20a0 : Nitrokey (Start, Pro, Storage)
            - 2581 : Nitrokey 3
            - 349e : Token2

          Seules les clés de ces vendors déclencheront le lock. Mettre `[]`
          pour désactiver (équivalent à `lockOnRemoval.enable = false;`).
        '';
        example = [
          "1050"
          "20a0"
        ];
      };
    };
  };

  config = mkIf cfg.enable {
    environment.etc."u2f-mappings".text = ''
      ${concatStringsSep "\n" (
        mapAttrsToList (username: keys: ''
          # Clés U2F de ${username}
          ${username}:${concatStringsSep ":" keys}
        '') cfg.keys
      )}
    '';
    security.pam.u2f = {
      enable = true;
      # Les clés U2F sont un remplacement suffisant des mots de passe.
      control = "sufficient";
      settings = {
        inherit (cfg) origin;
        appid = cfg.appId;
        authfile = "/etc/u2f-mappings";
        cue = true;
      };
    };

    # --- Lock-on-removal : udev → trigger systemd ---
    services.udev.extraRules = mkIf cfg.lockOnRemoval.enable (
      concatMapStringsSep "\n" (vid: ''
        ACTION=="remove", SUBSYSTEM=="usb", ATTRS{idVendor}=="${vid}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="securix-lock-on-key-removal.service"
      '') cfg.lockOnRemoval.vendorIds
    );

    systemd.services.securix-lock-on-key-removal = mkIf cfg.lockOnRemoval.enable {
      description = "Verrouille toutes les sessions graphiques au retrait d'une clé FIDO2";
      documentation = [
        "https://cyber.gouv.fr/publications/recommandations-relatives-ladministration-securisee-des-si"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/loginctl lock-sessions";
        # Pas besoin d'ordering vis-à-vis des sessions utilisateur — loginctl
        # parle à logind via dbus.
      };
    };
  };
}
