# SPDX-FileCopyrightText: 2026 Mattias Kockum <mattias@kockum.net>
#
# SPDX-License-Identifier: MIT

{ lib, config, ... }:
let
  userSubmodule = { name, ... }: {
    options = {
      email = lib.mkOption { type = lib.types.str; };
      username = lib.mkOption { type = lib.types.str; default = name; };
      hashedPassword = lib.mkOption { type = lib.types.str; };
      shell = lib.mkOption { type = lib.types.package; };
      isOperator = lib.mkOption { type = lib.types.bool; default = false; };
    };
  };
in
{
  options.securix.inventory.users = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule userSubmodule);
    default = { };
  };

  config = {
    users.users = lib.mapAttrs (_: user: {
      isNormalUser = true;
      hashedPassword = user.hashedPassword;
      shell = user.shell;
    }) (lib.filterAttrs
      (name: _: builtins.elem name config.securix.inventory.machine.users)
      config.securix.inventory.users
    );
  };
}
