<!-- 
SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>

SPDX-License-Identifier: MIT
-->

# Unreleased

## Features

- VPN profiles are now a NixOS option, `securix.vpn.profiles`, instead of an
  untyped module argument. They are typed, and can be contributed by any module:

  ```nix
  # in a team module
  securix.vpn.profiles.vpn-legal = { type = "ipsec"; … };
  
  # in a single machine's configuration
  securix.vpn.profiles.vpn-01.endpoint = lib.mkForce "vpn-staging.example.gouv.fr";
  ```

  The `vpnProfiles` parameter of `mkTerminal` keeps working and is now optional.

- `securix.self.user.allowedVPNs` is now typed as a plain list of strings.
  Referencing a VPN that does not exist in `securix.vpn.profiles` now raises an
  assertion naming both the offending user and the VPN.

## Breaking

- `availableHttpProxies` definition in `vpnProfiles` is deprecated, if you were using this option, you can replace it by something along these lines:

  ```nix
  services.automatic-http-proxy.networkmanager.events.handlers = {
    "10-ipsec-proxies" = {
      matchConnectionID = "VPN myvpn for $user";
      proxyToActuate = "myproxy";
    };
  };
  ```

  The advantage of this method is that you can refer to the context of the
  Securix system and do not suffer from
  https://github.com/cloud-gouv/securix/issues/195 limitations.

## Deprecated

- `_module.args.vpnProfiles` is now deprecated. Modules asking for `vpnProfiles` in
  their signature still work, but should read `config.securix.vpn.profiles`
  instead. The argument will be removed in a future release.
