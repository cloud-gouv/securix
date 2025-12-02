# SPDX-FileCopyrightText: 2025 Nixpkgs Contributors
# SPDX-FileContributor: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ pkgs, lib, ... }:
let
  inherit (pkgs.lib.generators) mkKeyValueDefault toKeyValue;
  inherit (lib)
    concatStringsSep
    mapAttrsToList
    isAttrs
    escape
    all
    attrValues
    ;
in
{
  # Plasma INI has a peculiar syntax which nests the top-level sections.
  # So we write a custom implementation of toINI for it.
  toPlasmaINI =
    {
      mkSectionName ? (name: escape [ "[" "]" ] name),
      mkKeyValue ? mkKeyValueDefault { } "=",
      listsAsDuplicateKeys ? false,
    }:
    attrsOfAttrs:
    let
      # map function to string for each key val
      mapAttrsToStringsSep =
        sep: mapFn: attrs:
        concatStringsSep sep (mapAttrsToList mapFn attrs);
      isAttrsOfAttrs = attrs: all isAttrs (attrValues attrs);
      mkSection =
        sectName: sectValues:
        if isAttrsOfAttrs sectValues then
          concatStringsSep "\n" (
            mapAttrsToList (
              subSectName: subSectValues: "[${mkSectionName sectName}]${mkSection subSectName subSectValues}"
            ) sectValues
          )
        else
          "[${mkSectionName sectName}]\n"
          + toKeyValue { inherit mkKeyValue listsAsDuplicateKeys; } sectValues;
    in
    # map input to ini sections
    mapAttrsToStringsSep "\n" mkSection attrsOfAttrs;
}
