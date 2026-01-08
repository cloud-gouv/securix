# SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  # Default exceptions for MACs.
  security.anssi.exceptions = {
    R37.rationale = "No MAC implementation is available on NixOS at the moment.";
    R45.rationale = "AppArmor is partially supported on NixOS.";
    R46.rationale = "SELinux is unsupported on NixOS.";
    R47.rationale = "SELinux is unsupported on NixOS.";
    R48.rationale = "SELinux is unsupported on NixOS.";
    R49.rationale = "SELinux is unsupported on NixOS.";
  };
}
