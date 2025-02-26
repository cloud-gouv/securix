# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  imports = [
    # This enables any operator to upgrade their system without compromising the security.
    ./permissionless-upgrade.nix
    # This continuously pulls as long as we have Internet the newest code for our infrastructure repository.
    ./automatic-pull.nix
  ];
}
