# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{ ... }:
{
  config = {
    services.openssh.enable = true;
    # TODO: when we will have build capacity, we can re-enable it.
    documentation.man.man-db.enable = false;
  };
}
