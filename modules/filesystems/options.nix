# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.securix.filesystems = {
    enable = mkEnableOption "automatic partitioning and filesystem setup" // {
      default = true;
    };

    # TODO(Ryan): use type merging too directly in the layout types.
    layout = mkOption {
      type = types.enum [
        "securix_v1"
        "office_v1"
      ];
      # This is the historical layout.
      default = "securix_v1";
      description = ''
        Layout that is used on this system.
        Filesystem layouts are notoriously hard to migrate.

        This is why we version our filesystems layouts based on our needs.

        Thanks to type merging in the NixOS system, you can extend this option with
        your own custom layout and use it on your systems.
      '';
    };
  };
}
