# SPDX-FileCopyrightText: 2026 Alexander McHugh <alexanderedwardmchugh@gmail.com>
#
# SPDX-License-Identifier: MIT

# Eval-only: a terminal without a graphical interface must pass its
# assertions, and selecting a variant without enabling it must not.
{ pkgs, libSecurix }:
let
  failedAssertions =
    graphical-interface:
    let
      terminal = libSecurix.mkTerminal {
        name = "headless";
        userSpecificModule = { };
        vpnProfiles = { };
        modules = [
          {
            securix = {
              inherit graphical-interface;
              self = {
                mainDisk = "/dev/nvme0n1";
                machine.hardwareSKU = "x280";
              };
            };
          }
        ];
      };
    in
    map (a: a.message) (builtins.filter (a: !a.assertion) terminal.system.config.assertions);

  headless = failedAssertions { };
  variantWithoutEnable = failedAssertions { variant = "sway"; };
in
assert headless == [ ];
assert
  variantWithoutEnable
  == [ "You must set `securix.graphical-interface.enable` to true to select a variant" ];
pkgs.runCommand "headless-terminal" { } "touch $out"
