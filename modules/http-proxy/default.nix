# SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  imports = [
    # Low-level configuration of g3proxy and proxy-switcher.
    ./http-proxy.nix
    # Authentication method to HTTP proxies via SSH forward, implemented as socket activated SSH units.
    ./ssh-forward.nix
  ];
}
