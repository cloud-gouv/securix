# SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>
#
# SPDX-License-Identifier: MIT

# Posture TLS sortant post-quantique.
#
# Par défaut, l'OpenSSL 3.x système de Sécurix négocie un échange de
# clés TLS 1.3 classique (X25519 / P-256). Un adversaire passif
# capturant les handshakes TLS aujourd'hui pourrait, une fois un CRQC
# disponible, dériver les clés de session rétroactivement et
# déchiffrer *tout* le trafic TLS capturé — le risque standard
# « harvest-now-decrypt-later » appliqué à chaque curl, git clone,
# requête DoT systemd-resolved, téléchargement de substituter Nix, etc.
#
# OpenSSL 3.5+ livre ML-KEM nativement (FIPS 203) dans son provider
# `default`, exposant les groupes hybrides standardisés
# `X25519MLKEM768`, `SecP256r1MLKEM768`, `X448MLKEM1024`,
# `SecP384r1MLKEM1024`. Cloudflare, Google, AWS et la majorité des
# gros déploiements TLS publient `X25519MLKEM768` depuis 2024. Ce
# module se contente d'activer ces hybrides dans la liste de
# préférence du ClientHello, avec X25519 / P-256 / P-384 classiques
# comme fallback d'interop.
#
# Scope : TLS sortant uniquement. N'affecte PAS :
#   * TLS entrant (sshd est configuré PQ séparément),
#   * les navigateurs : Firefox / Chromium utilisent leurs propres
#     stacks TLS (NSS / BoringSSL) et supportent déjà ML-KEM depuis
#     Firefox 132 / Chrome 124.
{ config, lib, ... }:
let
  cfg = config.securix.pqc.tls;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    concatStringsSep
    ;

  openssl-cnf = ''

    # Généré par modules/pqc-tls.nix (Sécurix)
    openssl_conf = openssl_init

    [openssl_init]
    providers = provider_sect
    ssl_conf = ssl_sect

    [provider_sect]
    default = default_sect

    [default_sect]
    activate = 1

    [ssl_sect]
    system_default = system_default_sect

    [system_default_sect]
    # Groupes TLS 1.3 publiés dans le ClientHello, ordre = préférence.
    # Le préfixe `?` dit à OpenSSL d'ignorer silencieusement tout nom
    # que le provider ne reconnaîtrait pas — robuste aux mises à jour
    # d'OpenSSL susceptibles de renommer des groupes.
    Groups = ${concatStringsSep ":" cfg.groups}
    MinProtocol = ${cfg.minProtocol}
  '';
in
{
  options.securix.pqc.tls = {
    enable = mkEnableOption ''

      l'échange de clés hybride post-quantique pour le TLS sortant, en
      utilisant les groupes ML-KEM livrés nativement par OpenSSL 3.5+
      (FIPS 203)
    '';

    groups = mkOption {
      type = types.listOf types.str;
      default = [
        # Hybride PQ, le plus préféré — NIST FIPS 203 ML-KEM-768 associé
        # à X25519 classique. Publié par Cloudflare, Google, AWS,
        # la plupart des CDN depuis mi-2024.
        "?X25519MLKEM768"
        # Hybride alternatif sur courbe NIST, même payload ML-KEM-768.
        "?SecP256r1MLKEM768"
        # Niveau de sécurité plus élevé (ML-KEM-1024) pour anticiper
        # les évolutions.
        "?X448MLKEM1024"
        # Fallback classique, requis pour l'interop TLS 1.3 avec les
        # serveurs qui ne parlent pas encore PQ.
        "X25519"
        "P-256"
        "P-384"
      ];
      description = ''

        Noms de groupes TLS 1.3 publiés dans le ClientHello, dans
        l'ordre de préférence. Les entrées préfixées par `?` sont
        silencieusement ignorées si OpenSSL ne connaît pas le nom (de
        sorte que la config survive aux renommages de groupes entre
        versions d'OpenSSL). Au moins une entrée sans `?` DOIT être
        une courbe classique pour l'interop avec les serveurs qui ne
        parlent pas PQ.
      '';
    };

    minProtocol = mkOption {
      type = types.str;
      default = "TLSv1.2";
      description = ''

        Version TLS minimale autorisée. TLSv1.2 est le plancher
        Sécurix ; TLS 1.0 / 1.1 sont refusés au niveau config.
        Mettre `"TLSv1.3"` pour refuser toute négociation en dessous
        de 1.3 — plus sûr mais peut casser des services internes
        mal configurés.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Pointe OpenSSL vers notre configuration via le chemin système
    # standard. NixOS ne remplit pas /etc/ssl/openssl.cnf par défaut,
    # donc on ne surcharge aucun fichier existant.
    environment.etc."ssl/openssl.cnf".text = openssl-cnf;

    # Garantit que les applications qui chargent leur propre contexte
    # OpenSSL reprennent aussi cette configuration.
    environment.variables.OPENSSL_CONF = "/etc/ssl/openssl.cnf";
  };
}
