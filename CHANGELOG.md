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

- `anssi-nixos-compliance-check` colours each rule from its check's exit
  status (0 passed, 2 not implemented, other failed) instead of matching
  words in its output: R12 was always red and a failing R7 green. R1, R2,
  R4, R5 and R6 report themselves as not implemented, and an unreadable
  sysctl is reported as a failure
  (https://github.com/cloud-gouv/securix/issues/293).
- `system-infrastructure-sync` no longer stays stuck in a permanent failed
  state after hitting systemd's `StartLimit` on repeated errors (e.g. missing
  network, unready TPM2). The start rate limit is disabled and failures are
  retried with an exponential backoff capped at 4 hours, so an automatic
  upgrade always eventually runs.
