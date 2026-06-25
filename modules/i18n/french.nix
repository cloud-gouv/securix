# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
let
  cfg = config.securix.i18n.french;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.securix.i18n.french.enable = mkEnableOption "French customizations";
  config = mkIf cfg.enable {
    # Dictionnaire français
    programs.firefox.policies.ExtensionSettings."fr-dicollecte@dictionaries.addons.mozilla.org" = {
      install_url = "https://addons.mozilla.org/en-US/firefox/downloads/latest/dictionnaire_francais1/latest.xpi";
      installation_mode = "normal_installed";
    };
  };
}
