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

- A failed Secure Boot key enrollment is now reported: when sbctl refused to
  enroll (for instance because the boot chain loads option ROMs), the
  installer went on silently and the installed system booted with Secure
  Boot disabled and the firmware still in setup mode. The new
  `preprovisionOptions.secureBootEnrollFlags` (default `[ ]`) passes flags
  such as `--microsoft` or `--tpm-eventlog` to `sbctl enroll-keys`
  (https://github.com/cloud-gouv/securix/issues/287).
- `system-infrastructure-sync` no longer stays stuck in a permanent failed
  state after hitting systemd's `StartLimit` on repeated errors (e.g. missing
  network, unready TPM2). The start rate limit is disabled and failures are
  retried with an exponential backoff capped at 4 hours, so an automatic
  upgrade always eventually runs.
