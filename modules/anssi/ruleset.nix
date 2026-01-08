# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, ... }:
let
  loadRules = files: lib.mergeAttrsList (map import files);
in
loadRules [
  ./preboot.nix
  ./kernel-options.nix
  # ./kernel.nix
  # ./vfs.nix
  # ./users.nix
  # ./apparmor.nix
  # ./selinux.nix
  # ./journaling.nix
  # ./runtime-minimization.nix
  # ./hardening.nix
  # ./nss-hardening.nix
  # ./integrity.nix
  # ./mta.nix
]
