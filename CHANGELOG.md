<!-- 
SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>

SPDX-License-Identifier: MIT
-->

# Unreleased

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

## Fixed

- `system-infrastructure-sync` no longer stays stuck in a permanent failed
  state after hitting systemd's `StartLimit` on repeated errors (e.g. missing
  network, unready TPM2). The start rate limit is disabled and failures are
  retried with an exponential backoff capped at 4 hours, so an automatic
  upgrade always eventually runs.
