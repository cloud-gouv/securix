# SPDX-FileCopyrightText: 2026 Antoine Eiche <antoine.eiche@lewocorp.eu>
#
# SPDX-License-Identifier: MIT

# nixos-rebuild is wrapped to add the repository HEAD commit id to the added boot menu entry.
# Note the derivation produced by this nixos-rebuild wrapper then differs from the one produced from the repository itself since it injects the commit id via builtins.getEnv.
{
  writeShellApplication,
  nixos-rebuild,
  git,
}:
writeShellApplication {
  name = "nixos-rebuild";
  runtimeInputs = [
    nixos-rebuild
    git
  ];
  text = ''
    revision=$(git rev-parse HEAD)
    export NIXOS_LABEL_VERSION="''${revision:0:7}"
    nixos-rebuild "$@"
  '';
}
