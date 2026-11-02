# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  config,
  lib,
  options,
  ...
}:
let
  inherit (lib) mkIf;
  cfg = config.securix.graphical-interface;
in
{
  options.securix.graphical-interface = {
    enable = lib.mkEnableOption "the WM/DE interfaces";
    variant = lib.mkOption {
      type = lib.types.enum [
        "kde"
        "sway"
        "cinnamon"
      ];
      example = "kde";
    };

    terminalVariant = lib.mkOption {
      type = lib.types.enum [
        "default"
        "kitty"
        "alacritty"
      ];
      default = "default";
    };
  };

  imports = [
    ./plasma.nix
    ./cinnamon.nix
    ./sway
    ./fonts.nix
  ];

  config = {
    assertions = [
      {
        # `cfg ? variant` is always true: the attribute exists even when the
        # option has no value, so check whether it is defined instead.
        assertion = options.securix.graphical-interface.variant.isDefined -> cfg.enable;
        message = "You must set `securix.graphical-interface.enable` to true to select a variant";
      }
    ];

    services.libinput = mkIf cfg.enable { enable = true; };
  };
}
