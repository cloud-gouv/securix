<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>
SPDX-FileContributor: 2026 Xavier Maso <xavier.maso@beta.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# What is Sécurix?

An operating system developed at [DINUM](https://www.numerique.gouv.fr/), primarily for internal use, for building workstation environments that are declarative, reproducible and secure by default.
Based on [`NixOS`](https://nixos.org/), it allows to write configuration as code for defining users, programs, services, configurations, and more.

> [!NOTE]
> This project is **alpha**, no support is provided at this time.

## Goals

SécurixOS is a NixOS distribution developed by DINUM to equip secure computers for system administration, office and development to process Unclassified information initially and potentially Restricted information thereafter.

It is a secure PC model designed to allow access to production and other critical uses while guaranteeing a variable security level depending on the configuration used.

Thanks to NixOS, this model is re-instantiable for various use cases: multi-agent workstation, multi-level workstation, intranet-only workstation, etc. with different teams and VPN strains.

Built according to ANSSI recommendations: <https://cyber.gouv.fr/publications/recommandations-relatives-ladministration-securisee-des-si>.

## Licenses

Sécurix is distributed under the [MIT](https://github.com/cloud-gouv/securix/blob/main/LICENSES/MIT.txt) license. See the `LICENSES` folder for more details.
See also [How to contribute](../contributor/docs.md).
