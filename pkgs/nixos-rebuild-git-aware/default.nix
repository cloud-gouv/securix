# SPDX-FileCopyrightText: 2026 Antoine Eiche <antoine.eiche@lewocorp.eu>
#
# SPDX-License-Identifier: MIT

# nixos-rebuild is wrapped to add the repository HEAD commit id to the added boot menu entry.
# Note the derivation produced by this nixos-rebuild wrapper then differs from the one produced from the repository itself since it injects the commit id via builtins.getEnv.
# See https://github.com/nixos/nixpkgs/blob/ddce4d809a16b9f0614e76636063282f6fb02908/nixos/modules/misc/label.nix#L69 for details.
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
    if [ "$(git rev-parse --is-inside-work-tree 2>&1)" != "true" ]; then
        echo "error: the current directory must be a Git repository."
        exit 1
    fi
    revision=$(git rev-parse HEAD)
    export NIXOS_LABEL_VERSION="''${revision:0:7}"
    nixos-rebuild "$@"
  '';
}
