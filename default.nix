# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

# Securix OS generic toolkit entrypoint. 
# Use the library to build your OS images and more.
{ sources ? import ./npins
, pkgs ? import sources.nixpkgs { } 
, defaultTags ? [ ]
, edition ? "unbranded"
}:
let
  inherit (pkgs) lib;
in
{
  lib = import ./lib { inherit pkgs lib edition defaultTags sources; };
  modules = ./modules;
  shell = pkgs.mkShell {
    packages = [
      pkgs.reuse
    ];
  };
}
