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
in
{
  options.securix.inventory-generator = {
    enable = lib.mkEnableOption "Inventory generator HTML tool";
    repoOptionsPrefix = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Préfixe des options du repo dérivé (ex: 'bureautix'). Laisser null si pas de repo dérivé.";
      example = "bureautix";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "inventory-generator" ''
        TMPDIR=$(mktemp -d)
        trap "rm -rf ''$TMPDIR" EXIT

        SECURIX_SRC="${securixSrc}"
        NIX_PKGS="${pkgs.path}"
        REPO_SRC="${if repoSrc != null then toString repoSrc else ""}"
        REPO_PREFIX="${if cfg.repoOptionsPrefix != null then cfg.repoOptionsPrefix else ""}"

        echo "Chargement des options..."
        OPTIONS=$(${pkgs.nix}/bin/nix-instantiate --eval --strict --json -E "
          let
            pkgs = import $NIX_PKGS {};
            lib = pkgs.lib;

            securixFiles = lib.filter (f: lib.hasSuffix \".nix\" (toString f)) (
              lib.filesystem.listFilesRecursive $SECURIX_SRC/modules
              ++ lib.filesystem.listFilesRecursive $SECURIX_SRC/community
            );

            repoFiles =
              if \"$REPO_SRC\" == \"\" then []
              else lib.filter (f: lib.hasSuffix \".nix\" (toString f)) (
                lib.filesystem.listFilesRecursive $REPO_SRC
              );

            isOptionFile = f:
              let content = builtins.readFile f; in
              (lib.hasInfix \"mkOption\" content || lib.hasInfix \"mkEnableOption\" content)
              && (lib.hasInfix \"options.securix\" content
                  || (\"$REPO_PREFIX\" != \"\" && lib.hasInfix (\"options.$REPO_PREFIX\") content));

            optionFiles = builtins.filter isOptionFile (securixFiles ++ repoFiles);

            eval = lib.evalModules {
              modules = optionFiles ++ [ { _module.check = false; } ];
              specialArgs = {
                inherit pkgs lib;
                vpnProfiles = {};
                operators = {};
                edition = \"unbranded\";
                defaultTags = [];
                sources = {};
                securixSrc = $SECURIX_SRC;
                repoSrc = if \"$REPO_SRC\" == \"\" then null else $REPO_SRC;
              };
            };

            raw = lib.optionAttrSetToDocList (builtins.removeAttrs eval.options [ \"_module\" ]);
            filtered = builtins.filter (o: !o.internal && o.visible) raw;
            enableGroups = lib.unique (
              map (o: lib.removeSuffix \".enable\" o.name)
              (builtins.filter (o: lib.hasSuffix \".enable\" o.name) filtered)
            );

            resolveValue = d:
              if d == null then null
              else if !(builtins.isAttrs d && (d._type or \"\") == \"literalExpression\") then d
              else
                let text = lib.trim d.text; in
                if text == \"null\" then null
                else if text == \"true\" then true
                else if text == \"false\" then false
                else if text == \"[ ]\" || text == \"[]\" then []
                else if lib.hasPrefix \"\\\"\" text && lib.hasSuffix \"\\\"\" text
                then lib.removePrefix \"\\\"\" (lib.removeSuffix \"\\\"\" text)
                else null;

            resolveType = t:
              let name = if builtins.isString t then t else t.name or \"string\"; in
              if      name == \"boolean\"            then { kind = \"bool\"; }
              else if name == \"package\"            then { kind = \"package\"; }
              else if lib.hasInfix \"integer\" name  then { kind = \"int\"; }
              else if lib.hasPrefix \"list of\" name then { kind = \"list\"; }
              else if lib.hasPrefix \"one of\"  name then {
                kind = \"enum\";
                values = map lib.trim (lib.splitString \", \" (lib.removePrefix \"one of \" name));
              }
              else { kind = \"str\"; };

          in {
            schemaVersion = 1;
            inherit enableGroups;
            options = map (opt: {
              path = opt.name;
              description = opt.description or null;
              internal = opt.internal;
              visible = opt.visible;
              hasDefault = opt ? default;
              default = resolveValue (opt.default or null);
              example = resolveValue (opt.example or null);
              isEnable = lib.hasSuffix \".enable\" opt.name;
              enableGroup =
                let g = lib.concatStringsSep \".\" (lib.init (lib.splitString \".\" opt.name));
                in if lib.elem g enableGroups then g else null;
              type = resolveType (opt.type or \"string\");
            }) filtered;
          }
        ")

        cp ${./inventory-generator.html} ''$TMPDIR/inventory-generator.html
        cp ${./inventory-generator.css} ''$TMPDIR/inventory-generator.css
        ${pkgs.python3}/bin/python3 -c "
js = open('${./inventory-generator.js}').read()
opts = open('/dev/stdin').read()
open('$TMPDIR/inventory-generator.js', 'w').write(js.replace('@@SECURIX_OPTIONS@@', opts))
" <<< "''$OPTIONS"

        xdg-open ''$TMPDIR/inventory-generator.html
        sleep 5
      '')
    ];
  };
} 