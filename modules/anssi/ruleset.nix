# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, ... }:
let
  loadRules = files: lib.mergeAttrsList (map import files);
in
loadRules [
  ./preboot.nix
]
