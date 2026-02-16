# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

# The list of authorized users to manipulate an admin laptop.
# Basically, the inventory.
{
  operators,
  config,
  lib,
  ...
}:
let
  cfg = config.securix.users;
  self = config.securix.self;
  operatorGroups = [
    "networkmanager"
    "video" # webcam?
    "dialout" # console série
    "wireshark" # debuggage trames
    "tss" # tpm2
    "operator" # can upgrade the system permissionlessly
  ];
  mkOperator =
    { developerMode, hashedPassword }:
    {
      isNormalUser = true;
      inherit hashedPassword;
      extraGroups =
        # In developer mode, you are allowed to use `sudo`.
        optional developerMode "wheel" ++ operatorGroups;
    };
  mkAdmin =
    { hashedPassword }:
    {
      isNormalUser = true;
      inherit hashedPassword;
      extraGroups = operatorGroups ++ [ "wheel" ];
    };
  inherit (lib)
    mkMerge
    mkIf
    mkOption
    types
    mkEnableOption
    optional
    filterAttrs
    mapAttrs
    ;
in
{
  options.securix.users = {
    allowAnyOperator = mkEnableOption "the possibility for any operator to log in on this machine.";
    enableMutableUsers = mkEnableOption "the possibility for a user to change his password via passwd or an admin to create new accounts imperatively.";
  };

  config = mkMerge [
    (mkIf (self.username != null) {
      users.mutableUsers = cfg.enableMutableUsers;
      users.groups.operator = { };
      security.tpm2.enable = true;
      users.users.${self.username} = mkOperator {
        developerMode = self.developer or false;
        hashedPassword = self.hashedPassword;
      };
    })
    # We need to add all the other users then
    # and enable a user to decrypt the partition.
    (mkIf cfg.allowAnyOperator {
      users.users =
        mapAttrs
          (
            username: opCfg:
            let
              isSelf = username == self.username;
              
              effectiveOpCfg = if isSelf then (opCfg // {
                hashedPassword = opCfg.hashedPassword or self.hashedPassword;
                developer = opCfg.developer or self.developer or false;
              }) else (opCfg // {
                hashedPassword = opCfg.hashedPassword or "!";
                developer = opCfg.developer or false;
              });

              debugOp = lib.trace "User Module [${username}]: Using Password? ${if (effectiveOpCfg.hashedPassword != "!") then "YES" else "NO"}" effectiveOpCfg;
            in
            mkOperator {
              developerMode = debugOp.developer;
              inherit (debugOp) hashedPassword;
            }
          )
          # We need to filter out ourselves.
          (filterAttrs (username: _: username != self.username) operators);
    })
  ];
}
