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
    mapAttrs'
    nameValuePair
    ;
  cfg = config.securix.admins;
  accountOpts =
    { name, ... }:
    {
      options = {
        name = mkOption {
          type = types.str;
          default = name;
          description = "PAM name for this account";
        };

        tokens = mkOption {
          type = types.listOf types.str;
          description = "List of PAM U2F tokens that are allowed to connect to this account";
        };
      };
    };

  mkAdminAccount =
    _:
    { name, ... }:
    nameValuePair name {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };
  mkAdminU2F = _: { name, tokens, ... }: nameValuePair name tokens;
in
{
  options.securix.admins = {
    enable = mkEnableOption "local admins accounts for the IT staff";
    accounts = mkOption {
      type = types.attrsOf (types.submodule accountOpts);
      default = { };
      description = "Attribute set of admin accounts";
    };
  };
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.securix.pam.u2f.enable;
        message = ''
          PAM U2F is required to use the local admin accounts. There is no password.
          Set `securix.pam.u2f.enable = true;`
        '';
      }
    ];

    users.users = mapAttrs' mkAdminAccount cfg.accounts;
    securix.pam.u2f.keys = mapAttrs' mkAdminU2F cfg.accounts;
  };
}
