# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, ... }:
{
  imports = [
    ./options.nix
    # Here's a list of layouts that are supported by the Securix framework.
    # Migrating between layouts is not supported, you need to reinstall.
    ./securix_v1.nix
    ./securix_v2.nix
  ];
}
