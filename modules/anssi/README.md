<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>

SPDX-License-Identifier: MIT
-->

# ANSSI compliance module

This is a self-contained NixOS implementation of <https://messervices.cyber.gouv.fr/guides/recommandations-de-securite-relatives-un-systeme-gnulinux>.
It can be copy-pasted outside of Sécurix for your own needs.

## Compliance check

`anssi-nixos-compliance-check` runs the check of every enabled rule. Each
check exits 0 when it passes and with any other status when it fails. Rules
without a check script are shown as not implemented. The rules are shown in
green, yellow and red accordingly.

With `--json`, it prints the results as a machine-readable document:

```json
{
  "org.securix.anssi-compliance-check.v1": {
    "rules": {
      "R7": {
        "exitCode": 1,
        "output": "No IOMMU detected or not enabled.",
        "status": "failed"
      }
    }
  }
}
```

`status` is `passed`, `not-implemented` or `failed`.
