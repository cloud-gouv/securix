# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
# SPDX-FileContributor: 2026 Pamplemousse <xavier.maso@beta.gouv.fr>
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
  pkgs' = pkgs.appendOverlays [
    (import "${sources.portail}/nix/overlay.nix")
    (import ./pkgs/overlay.nix)
  ];
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

      nixfmt = {
        enable = true;
        stages = [ "pre-push" ];
        package = pkgs.nixfmt;
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
  docsEn =
    pkgs.runCommand "docs-en"
      {
        nativeBuildInputs = [
          pkgs.mdbook
          pkgs.mdbook-mermaid
        ];
      }
      ''
        cp -r ${./docs/manual/book-en} book-en
        chmod -R u+w book-en
        mdbook-mermaid install book-en
        mdbook build book-en --dest-dir $out
      '';
  docsFr =
    pkgs.runCommand "docs-fr"
      {
        nativeBuildInputs = [
          pkgs.mdbook
          pkgs.mdbook-mermaid
        ];
      }
      ''
        cp -r ${./docs/manual/book-fr} book-fr
        chmod -R u+w book-fr
        mdbook-mermaid install book-fr
        mdbook build book-fr --dest-dir $out
      '';
  docsAll = pkgs.runCommand "docs-all" { } ''
    mkdir -p $out/en $out/fr
    cp -r ${docsEn}/* $out/en/
    cp -r ${docsFr}/* $out/fr/
    cp ${./docs/manual/index.html} $out/index.html
  '';
  docs = docsAll // {
    inherit docsEn docsFr docsAll;
    en = docsEn;
    fr = docsFr;
    all = docsAll;
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
  inherit
    docs
    docsEn
    docsFr
    docsAll
    ;
  all = docsAll;
  shell = pkgs'.mkShell {
    packages = [
      pkgs'.npins
      pkgs'.mdbook
      pkgs'.mdbook-mermaid
      (pkgs'.callPackage "${sources.agenix}/pkgs/agenix.nix" { })
    ]
    ++ git-checks.enabledPackages;

    shellHook = lib.concatStringsSep "\n" [ git-checks.shellHook ];
  };
}
