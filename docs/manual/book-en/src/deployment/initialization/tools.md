<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Declare tools and programs

Declaring tools or programs is done using classic NixOS options, e.g. `environment.systemPackages`.

## Declare a tool for all users of the workstation

In the `common/tools.nix` file, you can add a package for everyone.

## Declare a tool for a subset of workstation users

In the `common/tools.nix` file, you can add a package conditionally depending on the workstation or user by inspecting `config.securix.self.user` or `config.securix.self.machine`.

## Declare a tool for a person

In the inventory file, you can add `environment.systemPackages` on a machine or on a person.
