# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT
{
  imports = [ ./module.nix ];
  disabledModules = [ "services/networking/g3proxy.nix" ];
}
