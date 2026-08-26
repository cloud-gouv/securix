# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

final: prev:
(import ./default.nix {
  inherit (final) callPackage;
  nixos-rebuild = prev.nixos-rebuild;
})
