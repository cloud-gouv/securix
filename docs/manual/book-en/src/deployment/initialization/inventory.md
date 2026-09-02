<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Manage static inventory: additions and removals

The SécurixOS project officially only supports static inventories for now, which are suitable for environments up to 300 users. Beyond that, it is possible to use static inventories but you should implement scale management techniques, i.e. generate the static inventory from an ITSM database, split inventory directories by distinguishing prefixes to avoid too many files in the same directory and so on.

The SécurixOS project plans to support dynamic inventories based on LDAP or OIDC, which would eliminate the need to pre-declare users in Git.

## How to add a new machine?

To add a new machine, simply add a new `.nix` file with its identifier (e.g. serial number, asset tag, internal inventory number) with the following content:

```nix
{
  securix.self.mainDisk = "/dev/nvme0n1"; # If it's an NVMe disk, otherwise /dev/sda if it's a SATA disk.
  securix.self.machine = {
    hardwareSKU = "x280"; # SKU for the hardware profile, here: X280.
    serialNumber = "PC140V35"; # Serial number, asset tag or internal inventory number, it is used to build the machine's hostname.

    users = [
      "heloise" # Users that will be provisioned on this machine. They must exist beforehand.
    ];
  };
}
```

## How to add a new person?

To add a new person, simply add a new `.nix` file with their user identifier (first name, first then last name, etc.):

```nix
{ pkgs, ... }:
{
  securix.self.user = {
    email = "heloise@example.com"; # Email address
    username = "heloise"; # Username
    # password is `test`
    hashedPassword = "$y$j9T$zk4xGLyshz7RzqnMX6M8O0$AybRelILMkQSWcQZV4s.ykRNi/UlgaCUaDwdee0n7N2"; # Hashed password with ycrypt
    defaultLoginShell = pkgs.zsh; # Optionally, shell for the user
  };
}
```

> ⚠️ Note, these Nix files do not live in a NixOS module for developers familiar with NixOS, this is a limitation documented by <https://github.com/cloud-gouv/securix/issues/196> that we want to lift.

All configurable options for a user are available at <https://github.com/cloud-gouv/securix/blob/main/modules/self.nix#L74-L140>.
