<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Quick Start

## 1. Copy the Skeleton Template

To get started, copy the skeleton `default.nix` file provided in the [examples/basic](../../../examples/basic) directory.

## 2. Create Users and Inventory

Next, create your system inventory. You can use the example structure provided by Bureautix here: [Bureautix example inventory](https://github.com/cloud-gouv/bureautix-example/tree/main/inventory).

In your inventory, you can organize items into two main sections: *machines* and *users*. Each machine can have a list of users assigned to it.

## 3. Customize Your System

At this point, you can customize your NixOS system. You have two options:

* Use the modules provided by Sécurix, such as `securix.firefox` for Firefox configuration.
* Alternatively, you can use standard NixOS modules for system customization.

## 4. Deploy the USB Installer

Sécurix provides a set of default attributes for each terminal:

* `installer`: This is a USB installer specific to the terminal. Booting from this USB will provide the `autoinstall-terminal` command to automatically install the system.
* `system`: This is the top-level NixOS attribute, useful for advanced deployment options.
