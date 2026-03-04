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
    { hashedPassword }:
    {
      isNormalUser = true;
      inherit hashedPassword;
      extraGroups = operatorGroups;
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
    (mkIf (self.user.username != null) {
      users.mutableUsers = cfg.enableMutableUsers;
      users.groups.operator = { };
      security.tpm2.enable = true;
      users.users.${self.user.username} = mkOperator { inherit (self.user) hashedPassword; };
    })
    # We need to add all the other users then
    # and enable a user to decrypt the partition.
    (mkIf cfg.allowAnyOperator {
      users.users =
        mapAttrs (username: config: mkOperator { inherit (config) hashedPassword; })
          # We need to filter out ourselves.
          (filterAttrs (username: _: username != self.username) operators);
    })
  ];
}
