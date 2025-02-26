# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, ... }:
{
  imports = [
    "${(import ../npins).disko}/module.nix"
    ./disko.nix
  ];
}
