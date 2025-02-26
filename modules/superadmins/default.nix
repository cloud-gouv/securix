# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types mkIf;
  cfg = config.securix.superadmins;
in
{
  options.securix.superadmins = {
    enable = mkEnableOption "l'administration à distance par les super-administrateurs";

    keys = mkOption {
      type = types.listOf types.str;
      description = "Liste de clefs SSH autorisés à se connecter à root@";
    };
  };
  config = mkIf cfg.enable {
    services.openssh.enable = true;
    users.users.root.openssh.authorizedKeys.keys = cfg.keys;
  };
}
