<!--
SPDX-FileCopyrightText: 2026 Quentin Cazier <cazierquentin@gmail.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Journal sealing

Journal sealing (Forward Secure Sealing, FSS) lets an administrator check that a system journal was not altered after the fact. A sealing key stays on the machine and changes automatically, a verification key is kept away from the machine. It partially addresses the ANSSI recommendations R76 and R77.

## Enable

```nix
securix.journaldFSS.enable = true;
```

The journal is then stored persistently and sealed.

## At install time

When the option is enabled, `autoinstall-terminal` generates the keys in the installed system once the system copy is done. It prints the verification key and a QR code, then waits for a confirmation. Write the key down or scan the QR code: it is not kept on the machine and cannot be recovered.

## Verify a journal

On the machine, with the verification key:

```sh
journalctl --verify --verify-key=<key>
```

Each verified file is reported as `PASS` or `FAIL`.

## Machines already installed

Enable the option, deploy the configuration, then generate the keys as root:

```sh
journalctl --setup-keys
journalctl --rotate
```

The rotation opens a new, sealed journal file. Earlier files stay unsealed.

## Limitations

Verification can fail wrongly on archived files when entries carry a timestamp later than the last seal, see systemd issue 17833. Keep the default sealing interval of fifteen minutes.

If the verification key is lost, generate a new pair with `journalctl --setup-keys --force`. Files sealed with the old key cannot be verified anymore.
