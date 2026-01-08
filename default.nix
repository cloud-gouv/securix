# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

# Securix OS generic toolkit entrypoint.
# Use the library to build your OS images and more.
{
  sourcesOverrides ? sources: sources,
  sources ? sourcesOverrides (import ./npins),
  pkgs ? import sources.nixpkgs { },
  defaultTags ? [ ],
  edition ? "unbranded",
}:
let
  # Import our own overlays.
  pkgs' = pkgs.extend (import ./pkgs/overlay.nix);
  git-hooks = import sources.git-hooks;

  inherit (pkgs') lib;

  git-checks = git-hooks.run {
    src = ./.;

    hooks = {
      statix = {
        enable = true;
        stages = [ "pre-push" ];
        settings.config = toString ./statix.toml;
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
  lib-securix = import ./lib {
    pkgs = pkgs';
    inherit
      lib
      edition
      defaultTags
      sources
      ;
  };
in
{
  lib = lib-securix;
  pkgs = pkgs';
  modules = ./modules;
  tests = import ./tests {
    pkgs = pkgs';
    libSecurix = lib-securix;
  };
  shell = pkgs'.mkShell {
    packages = [
      pkgs'.npins
      pkgs'.mdbook
      (pkgs'.callPackage "${sources.agenix}/pkgs/agenix.nix" { })
    ]
    ++ git-checks.enabledPackages;

    shellHook = lib.concatStringsSep "\n" [ git-checks.shellHook ];
  };
}
