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

## Added

- `securix.audit` now applies the ANSSI-BP-028 R73 audit rule set: program
  execution, kernel module loading, kexec, mounts, ptrace, hostname changes,
  file deletion, denied file access, changes under `/etc`, and access to the
  audit trail and tools. Every syscall rule also covers the 32-bit ABI, and
  every rule has a key for `ausearch -k`. New options: `securix.audit.lockRules`
  makes the rules immutable until reboot, and `securix.audit.extraRules` adds
  site-specific rules.

## Fixed

- With `securix.audit.enable`, `/etc/audit/auditd.conf` no longer contains
  conflicting duplicate settings from both Sécurix and NixOS.
- With `securix.audit.enable`, audit events are no longer dropped during
  boot: the kernel backlog is raised to 32768.
- `system-infrastructure-sync` no longer stays stuck in a permanent failed
  state after hitting systemd's `StartLimit` on repeated errors (e.g. missing
  network, unready TPM2). The start rate limit is disabled and failures are
  retried with an exponential backoff capped at 4 hours, so an automatic
  upgrade always eventually runs.
