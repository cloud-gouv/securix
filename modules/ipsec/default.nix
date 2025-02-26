# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  imports = [
    # IPsec tunnel
    # System-level StrongSwan.
    ./networkmanager.nix
    # Firewall rules to go always to the IPsec tunnel
    ./firewall.nix
  ];
}
