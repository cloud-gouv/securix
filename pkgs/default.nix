# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ callPackage }:
{
  mkPlasmaLookAndFeelPackage = callPackage ./plasma/mk-look-and-feel-package.nix { };
}
