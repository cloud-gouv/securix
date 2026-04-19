<!--
SPDX-FileCopyrightText: 2026 Aurélien Ambert <aurelien.ambert@proton.me>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Enrolling a FIDO2 security key

This page describes how to register a FIDO2 security key against a
Sécurix account. `pamu2fcfg` is shipped by default (see
`modules/security-keys.nix`); no ad-hoc `nix-shell` is needed.

## 1. Prerequisites

- A physical FIDO2 key (YubiKey 4/5, Security Key, Nitrokey 3, …)
  plugged into a USB port of the Sécurix workstation.
- A shell opened as the *target user* (not `root`). `pamu2fcfg`
  writes its output to stdout, so no privilege escalation is
  required for generation itself.
- `securix.pam.u2f.enable = true` in the system configuration —
  this is what instructs `pam_u2f(8)` to consult
  `/etc/u2f-mappings` during authentication; without it, the
  generated credential is never consulted by PAM and the enrolment
  has no effect. It is already set implicitly when you use
  `securix.admins` for account management.

## 2. Generate the U2F credential

`HOSTNAME` scopes the credential to the workstation (default
`pam://$HOSTNAME`). If a fleet shares a single logical workstation
identity (same `appId` across several physical machines — for
example, a homogeneous deployment behind the same DNS name where a
user may roam between seats), set `securix.pam.u2f.appId` to a
common value and pass it to the command below; otherwise accept
the per-host default.

```bash
# On the Sécurix workstation — touch the key when it flashes.
pamu2fcfg --appid="pam://$HOSTNAME" --origin="pam://$HOSTNAME"
```

Typical output (one line per key):

```
operator:XXXXXXXXXX…base64…XXXXXXXXXX,YYYYYYYYYY…pubkey…YYYYYYYYYY
```

The part after `:` is the `u2f_key` value to carry into the Nix
configuration.

## 3. Declare the key in configuration

### For an admin account (`securix.admins.accounts`)

```nix
{
  securix.admins = {
    enable = true;
    accounts.alice.u2f_keys = [
      # primary key
      "XXXXXXXXXX…base64…XXXXXXXXXX,YYYYYYYYYY…pubkey…YYYYYYYYYY"
      # backup key (recommended — see §4)
      "ZZZZZZZZZZ…backup…ZZZZZZZZZZ,WWWWWWWWWW…backup…WWWWWWWWWW"
    ];
  };
}
```

### For a standard operator (inventory-driven `mkTerminals`)

See `examples/basic/default.nix` for the full `inventory` pattern.

## 4. Backup key (strongly recommended)

Yubico's own deployment guidance
([docs.yubico.com — Deployment Best Practices][yubico-dep]) and
FIDO Alliance guidance
([FIDO UAF / U2F deployment recommendations][fido-dep]) both
recommend enrolling at least two hardware authenticators per user.
Losing the single key otherwise makes the workstation unreachable
until reprovisioning.

[yubico-dep]: https://docs.yubico.com/software/yubikey/deployment-best-practices.html
[fido-dep]: https://fidoalliance.org/specs/fido-v2.2-rd-20230321/fido-security-ref-v2.2-rd-20230321.html

Procedure:

1. Repeat step 2 with the second key inserted.
2. Append the new line to the `u2f_keys` list (pam_u2f accepts N
   keys per account; the first one that answers validates the
   authentication).
3. Deploy the new generation (`nixos-rebuild switch`).
4. Store the backup key in a **physical safe separate from the
   workstation**.

## 5. Recovery path (single key lost without backup)

The LUKS recovery key that Sécurix captures at install time (see
`docs/manual/src/user/deployment.md`) unlocks the **disk**; it
does *not* unlock a PAM login. The two mechanisms are independent:

| Key | Unlocks | Where stored |
|---|---|---|
| FIDO2 key (this page) | PAM auth after `securix.pam.u2f.enable` | `/etc/u2f-mappings` |
| LUKS recovery key | LUKS volume at boot | Operator-managed (password manager / safe) |

Recovering from a lost FIDO2 key without a backup therefore
requires an operator with existing access (via their own FIDO2
key or `root` serial console) to deploy a new generation
enrolling a new key for the affected account. Rescue from bare
metal without any authenticated access paths is not supported.

## 6. Rotation and revocation

To remove a compromised key: delete the matching line from
`u2f_keys`, deploy, and verify that authentication fails with the
old key and succeeds with the replacement.

To rotate every key of a user: generate new credentials on every
physical key (step 2), replace the whole list, deploy.

## 7. Troubleshooting

- **`pamu2fcfg` prints "error: device not found"** — the key is
  not detected. Check `lsusb` and the udev rules installed by
  `services.udev.packages`.
- **`pamu2fcfg` prints "touch key"** but never completes — wait
  for the blink, then touch the metal contact.
- **Enrolment succeeds but login fails** — verify that
  `securix.pam.u2f.appId` has the same value at enrolment and at
  authentication (the value is baked into `/etc/u2f-mappings`).

## References

- [ANSSI — Administration sécurisée des SI](https://cyber.gouv.fr/publications/recommandations-relatives-ladministration-securisee-des-si)
- [`pam_u2f` manpage — Yubico](https://developers.yubico.com/pam-u2f/Manuals/pam_u2f.8.html)
- [`pamu2fcfg` manpage — Yubico](https://developers.yubico.com/pam-u2f/Manuals/pamu2fcfg.1.html)
