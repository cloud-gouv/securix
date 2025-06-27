# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.securix.password-manager.bitwarden;
  inherit (lib)
    types
    mkOption
    mkEnableOption
    mkIf
    ;
in
{
  options.securix.password-manager.bitwarden = {
    enable = mkEnableOption "l'intégration fine à un serveur Bitwarden d'équipe";

    baseUri = mkOption {
      type = types.str;
      example = "https://vaultwarden.acme.corp";
    };
  };

  config = mkIf cfg.enable {
    programs.goldwarden.enable = true;

    systemd.user.services.goldwarden.serviceConfig.ExecStartPost =
      pkgs.writeShellScript "preconfigure-goldwarden" ''
        ${lib.getExe config.programs.goldwarden.package} config set-api-url ${cfg.baseUri}/api
        ${lib.getExe config.programs.goldwarden.package} config set-identity-url ${cfg.baseUri}/identity
        ${lib.getExe config.programs.goldwarden.package} config set-notifications-url ${cfg.baseUri}/notifications
        echo "Goldwarden preconfigured for ${cfg.baseUri} instance"
      '';
  };
}
