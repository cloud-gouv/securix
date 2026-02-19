# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

final: prev:
  let
    defaults = import ./default.nix { inherit (final) callPackage; };
    openbaoPatch = import ./openbao-patch.nix final prev;
  in
  defaults // openbaoPatch
