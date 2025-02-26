# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

# The list of authorized users to manipulate an admin laptop.
# Basically, the inventory.
{ operators, config, lib, ... }: 
let
  cfg = config.securix.users;
  self = config.securix.self;
  mkOperator = { developerMode, hashedPassword }: {
    isNormalUser = true;
    inherit hashedPassword;
    extraGroups = 
      # In developer mode, you are allowed to use `sudo`.
      optional developerMode "wheel" ++ [
        "networkmanager"
        "video" # webcam?
        "dialout" # console série
        "wireshark" # debuggage trames
        "tss" # tpm2
        "operator" # can upgrade the system permissionlessly
      ];
  };
  inherit (lib) mkMerge mkIf mkEnableOption optional filterAttrs mapAttrs;
in
{
  options.securix.users = {
    allowAnyOperator = mkEnableOption "the possibility for any operator to log in on this machine.";
  };

  config = mkMerge [
    {
      users.mutableUsers = false;
      users.groups.operator = {};
      security.tpm2.enable = true;
      users.users.${self.username} = mkOperator {
        developerMode = self.developer;
        inherit (self) hashedPassword;
      };
    }
    # We need to add all the other users then
    # and enable a user to decrypt the partition.
    (mkIf cfg.allowAnyOperator {
      users.users = mapAttrs (username: config: mkOperator {
        developerMode = config.developer;
        inherit (config) hashedPassword;
      }) 
      # We need to filter out ourselves.
      (filterAttrs (username: _: username != self.username) operators);
    })
  ];
}
