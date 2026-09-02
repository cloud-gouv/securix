<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Context

The SécurixOS project is a workstation building kit, whether for administration or for office use and everything in between in terms of workstation nuances, e.g. specialized use-case workstation, hardened nomad workstation, etc.

The project builds on the NixOS project, which itself is a Linux distribution building kit inheriting Nix concepts [1] and specializes it for the purpose of building organizationally managed workstations.

The SécurixOS project does not address workstation needs in BYOD ("Bring Your Own Device") environments; it only addresses managed workstations under the control of a centralized entity within an organization. It is of course possible to manage several SécurixOS strains under different branches within the same organization, if necessary.

Since SécurixOS is a building kit, it does not provide "off-the-shelf" installation artifacts like classic Linux distributions, so it is not possible to download a SécurixOS ISO to try it out as you would need to fabricate a fake organization and have a demonstration workstation infrastructure.

Nevertheless, the SécurixOS project offers example code repositories to see **one** way to integrate the SécurixOS kit to obtain all kinds of artifacts: ISOs, systems to copy to disk, virtual machine images, etc.

The SécurixOS project assumes that those who take it on already have an understanding of the Nix or NixOS ecosystem; it is not advisable to use SécurixOS without Nix skills within your organization.

## Distinction between `securix` and `securix-$org` or `bureautix-$org`

In the SécurixOS project, we recommend keeping a reference to the open source project and pooling efforts in the digital commons when your need could benefit everyone. When your need is very specific to your organization or experimental, it is preferable to keep it to yourself and mature it. In addition, the SécurixOS project offers many mechanisms to control the policies applied to generate your organization's workstations. This information must be stored in a code repository, we call them `securix-$org` repositories (if you use an admin workstation variant) or `bureautix-$org` (if you use an office variant), where you find:

* your organization-specific customizations
* your experiments
* your static inventories
* your VPN configuration items
* your proxy configuration items

For example, if your organization `acme` decides to deploy an admin workstation and an office workstation (two populations, sometimes overlapping) under the management of two different divisions, you can then build `securix-acme` and `bureautix-acme` and they will both refer to the open source project <https://github.com/cloud-gouv/securix>. It is of course possible to mirror this project on your forge and depend on the mirrored version.

Thus, for upgrades, there are two major components to manage:

* NixOS & nixpkgs which is updated every 6 months if you follow stable versions or every week if you follow rolling versions
* SécurixOS which is developed continuously and maintains security components that are not in nixpkgs, e.g. lanzaboote for Secure Boot or disko for disk partitioning.
