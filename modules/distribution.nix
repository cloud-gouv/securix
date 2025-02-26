# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ lib, ... }:
{
  system.nixos.distroId = lib.mkDefault "securix";
  system.nixos.distroName = lib.mkDefault "Sécurix";
  system.stateVersion = "24.11";
}
