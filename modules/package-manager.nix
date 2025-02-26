# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ pkgs, ... }: {
  nix.package = pkgs.lix;
  nix.nixPath = [
    # Always point to the authorized sources.
    "nixpkgs=${pkgs.path}"
  ];
}
