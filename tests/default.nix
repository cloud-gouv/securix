# SPDX-FileCopyrightText: 2025 Antoine Eiche <aei.ext@hackcyom.com>
# SPDX-FileContributor: 2026 Xavier Maso <xavier.maso@beta.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ pkgs, libSecurix }: {
  minimal = import ./minimal.nix { inherit pkgs libSecurix; };
  anssi-minimal = import ./anssi-minimal.nix { inherit pkgs libSecurix; };
  idempotent-autoinstall = import ./idempotent-autoinstall.nix { inherit pkgs libSecurix; };
  portail = import ./portail.nix { inherit pkgs libSecurix; };
  tools = import ./tools.nix { inherit pkgs libSecurix; };
  vpn-ipsec-shutdown = import ./vpn-ipsec-shutdown.nix { inherit pkgs libSecurix; };
}
