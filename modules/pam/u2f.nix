# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    concatStringsSep
    mapAttrsToList
    ;
  cfg = config.securix.pam.u2f;
in
{
  options.securix.pam.u2f = {
    enable = mkEnableOption "the usage of U2F to log in to local accounts";
    appId = mkOption {
      type = types.str;
      default = "pam://$HOSTNAME";
      description = "Application identifier for the keys that should be detected for this system";
      example = "pam://acme-corp-workstations";
    };
    origin = mkOption {
      type = types.str;
      default = "pam://$HOSTNAME";
      description = "Origin identifier for the keys that should be detected for this system";
      example = "pam://acme-corp-workstations";
    };
    keys = mkOption {
      type = types.attrsOf (types.listOf types.str);
      description = "An attribute set of accounts and their key mappings";
    };
  };

  config = mkIf cfg.enable {
    environment.etc."u2f-mappings".text = ''
      ${concatStringsSep "\n" (
        mapAttrsToList (username: keys: ''
          # ${username} U2F keys
          ${username}:${concatStringsSep ":" keys}
        '') cfg.keys
      )}
    '';
    security.pam.u2f = {
      enable = true;
      # U2F are sufficient replacements to passwords.
      control = "sufficient";
      settings = {
        inherit (cfg) origin;
        appid = cfg.appId;
        authfile = "/etc/u2f-mappings";
      };
    };
  };
}
