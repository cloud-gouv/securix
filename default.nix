# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

# Securix OS generic toolkit entrypoint.
# Use the library to build your OS images and more.
{
  sources ? import ./npins,
  pkgs ? import sources.nixpkgs { },
  defaultTags ? [ ],
  edition ? "unbranded",
}:
let
  git-hooks = import sources.git-hooks;

  inherit (pkgs) lib;

  git-checks = git-hooks.run {
    src = ./.;

    hooks = {
      statix = {
        enable = true;
        stages = [ "pre-push" ];
        settings.ignore = [ "**/npins" ];
      };

      nixfmt-rfc-style = {
        enable = true;
        stages = [ "pre-push" ];
        package = pkgs.nixfmt-rfc-style;
        args = [ "-s" ];
      };

      reuse = {
        enable = true;
        stages = [ "pre-push" ];
        package = pkgs.reuse;
      };
    };
  };
in
{
  lib = import ./lib {
    inherit
      pkgs
      lib
      edition
      defaultTags
      sources
      ;
  };
  modules = ./modules;
  shell = pkgs.mkShell {
    packages = [
      pkgs.npins
      (pkgs.callPackage "${sources.agenix}/pkgs/agenix.nix" { })
    ] ++ git-checks.enabledPackages;

    shellHook = lib.concatStringsSep "\n" [ git-checks.shellHook ];
  };
}
