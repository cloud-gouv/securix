# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  pkgs,
  lib,
  stdenv,
  writeText,
  writers,
  makeDesktopItem,
  xorg,
}:
{
  name,
  version,
  metadata,
  defaults,
  icons,
  launcherIcon,
  wallpapers,
  previews ? null,
  splash ? null,
}:
let
  inherit (lib) optionalString;
  inherit (import ./lib.nix { inherit pkgs lib; }) toPlasmaINI;
  toPlasmaINI' = toPlasmaINI { };
  id = metadata.id or (throw "Plugin '${name}' must have an ID in `metadata` field");
  mkCopyContents = inode: target: ''
    # Copy and dereferencing ${target}
    cp -rLv ${inode} ${target}
  '';
  pluginRoot = "$out/share/plasma/look-and-feel/${id}";
  symlinkStaticContents = ''
    ${mkCopyContents wallpapers "$out/share/wallpapers"}
    ${mkCopyContents icons "$out/share/icons"}
    ${optionalString (previews != null) (mkCopyContents previews "${pluginRoot}/contents/previews")}
    ${optionalString (splash != null) (mkCopyContents splash "${pluginRoot}/contents/splash")}
  '';

  mkApplicationLauncherJSApplet =
    iconName:
    writeText "org.kde.plasma.kickoff.js" ''
      applet.currentConfigGroup = ['General'];
      applet.writeConfig('icon', '${iconName}');
      applet.reloadConfig();
    '';

  # Emit one types:
  # - org.kde.plasma.kickoff.js for application launcher logo
  writePlasmoidScripts = ''
    mkdir -p ${pluginRoot}/contents/plasmoidsetupscripts
    cp -Lv ${mkApplicationLauncherJSApplet launcherIcon} ${pluginRoot}/contents/plasmoidsetupscripts/org.kde.plasma.kickoff.js
  '';

  # Transform the defaults tree into a INI-style file.
  writeDefaults =
    let
      defaultsFile = writeText "defaults" (toPlasmaINI' defaults);
    in
    ''
      cp -Lv ${defaultsFile} ${pluginRoot}/contents/defaults
    '';

  # Transform the metadata tree into a JSON and a desktop file.
  writeMetadataFiles =
    let
      jsonFile = writers.writeJSON "${name}-metadata.json" {
        KPlugin = {
          Authors = [
            {
              Name = "Securix authors";
              Email = "contact@securix.fr";
            }
          ];
          Category = metadata.category or "";
          Description = metadata.description or "";
          Id = metadata.id;
          License = metadata.license or "Proprietary";
          Name = name;
          Version = version;
          Website = metadata.website or "";
        };

        KPackageStructure = "Plasma/LookAndFeel";
        X-Plasma-APIVersion = "2";
      };
    in
    ''
      ln -s ${jsonFile} ${pluginRoot}/metadata.json
    '';

in
stdenv.mkDerivation {
  pname = name;
  inherit version;

  dontUnpack = true;
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p ${pluginRoot}/contents

    echo symlinking static contents
    ${symlinkStaticContents}
    echo symlinked static contents

    echo writing default plasmoid scripts
    ${writePlasmoidScripts}
    echo wrote plasmoid scripts

    echo writing plugin defaults
    ${writeDefaults}
    echo wrote defaults

    echo writing metadata files
    ${writeMetadataFiles}
    echo wrote metadata files

    runHook postInstall
  '';
}
