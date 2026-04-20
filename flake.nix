# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  description = "Sécurix — Base OS sécurisé pour poste d'administration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    agenix.url = "github:ryantm/agenix";
    disko.url = "github:nix-community/disko/v1.9.0";
    lanzaboote.url = "github:nix-community/lanzaboote/v0.4.2";
    git-hooks.url = "github:cachix/git-hooks.nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      agenix,
      disko,
      lanzaboote,
      git-hooks,
    }:
    let
      system = "x86_64-linux";
      securix = import ./. {
        pkgs = nixpkgs.legacyPackages.${system};
        sourcesOverrides = _: {
          inherit
            nixpkgs
            agenix
            disko
            lanzaboote
            git-hooks
            ;
        };
      };
    in
    {
      lib = securix.lib;
      legacyPackages.${system} = securix.pkgs;
      nixosModules.default = securix.modules;
      checks.${system} = securix.tests;
      devShells.${system}.default = securix.shell;
    };
}
