# SPDX-FileCopyrightText: 2025 Antoine Eiche <aei.ext@hackcyom.com>
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }:
{
  minimal = import ./minimal.nix { inherit pkgs libSecurix; };
  anssi-minimal = import ./anssi-minimal.nix { inherit pkgs libSecurix; };
}
