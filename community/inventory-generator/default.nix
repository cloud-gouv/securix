# SPDX-FileCopyrightText: 2026 Pauline Legrand <pauline.legrand@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  config,
  lib,
  pkgs,
  securixSrc,
  repoSrc ? null,
  ...
}:

let
  cfg = config.securix.inventory-generator;

  # Chemin vers le repo (optionnel)
  repoArg = if repoSrc != null then "${repoSrc}" else "";

  optionsJson = pkgs.runCommand "securix-options-json"
    { nativeBuildInputs = [ pkgs.python3 ]; }
    ''
      python3 ${./parse-options.py} ${securixSrc} ${repoArg} > $out
    '';

  inlineScript = pkgs.writeText "inline-options.py" ''
    import sys
    js      = open(sys.argv[1]).read()
    options = open(sys.argv[2]).read()
    result  = js.replace('@@SECURIX_OPTIONS@@', options)
    open(sys.argv[3], 'w').write(result)
  '';

  pkg = pkgs.runCommand "inventory-generator"
    { nativeBuildInputs = [ pkgs.python3 ]; }
    ''
      mkdir -p $out/share/inventory-generator

      cp ${./inventory-generator.html} $out/share/inventory-generator/inventory-generator.html
      cp ${./inventory-generator.css}  $out/share/inventory-generator/inventory-generator.css

      python3 ${inlineScript} \
        ${./inventory-generator.js} \
        ${optionsJson} \
        $out/share/inventory-generator/inventory-generator.js
    '';
in
{
  options.securix.inventory-generator = {
    enable = lib.mkEnableOption "Inventory generator HTML tool";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "inventory-generator" ''
        xdg-open ${pkg}/share/inventory-generator/inventory-generator.html
      '')
    ];
  };
}
