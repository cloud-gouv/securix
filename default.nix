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

      zizmor = {
        enable = true;
        stages = [ "pre-push" ];
        package = pkgs.zizmor;
        entry = "zizmor .github/workflows/ --offline";
        pass_filenames = false;
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
  mkDocs =
    { src, suffix }:
    pkgs.runCommand "docs-${suffix}"
      {
        nativeBuildInputs = [
          pkgs.mdbook
          pkgs.mdbook-mermaid
        ];
      }
      ''
        cp -r ${src} book-${suffix}
        chmod -R u+w book-${suffix}
        mdbook-mermaid install book-${suffix}
        mdbook build book-${suffix} --dest-dir $out
      '';
  docsEn = mkDocs {
    src = ./docs/manual/book-en;
    suffix = "en";
  };
  docsFr = mkDocs {
    src = ./docs/manual/book-fr;
    suffix = "fr";
  };
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
