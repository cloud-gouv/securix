# SPDX-FileCopyrightText: 2026 Mattias Kockum <mattias@kockum.net>
#
# SPDX-License-Identifier: MIT

{ lib, config, ... }:
{
  options.securix.inventory.machine = lib.mkOption {
    default = { };
    type = lib.types.submodule {
      options = {
        hardwareSKU = lib.mkOption { type = lib.types.str; default = ""; };
        serialNumber = lib.mkOption { type = lib.types.str; default = ""; };
        mainDisk = lib.mkOption { type = lib.types.str; default = ""; };
        users = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      };
    };
  };

  config = {
    securix.self.mainDisk = lib.mkDefault config.securix.inventory.machine.mainDisk;
    securix.self.machine.hardwareSKU = lib.mkDefault config.securix.inventory.machine.hardwareSKU;
    securix.self.machine.serialNumber = lib.mkDefault config.securix.inventory.machine.serialNumber;

    assertions = map (username: {
      assertion = config.securix.inventory.users ? ${username};
      message = "Machine '${config.securix.inventory.machine.serialNumber}' "
        + "references user '${username}' who does not exist in "
        + "securix.inventory.users.";
    }) config.securix.inventory.machine.users;
  };
}
