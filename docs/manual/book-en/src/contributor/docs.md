<!--
SPDX-FileCopyrightText: 2026 Antoine Eiche <antoine.eiche@lewocorp.eu>
SPDX-FileContributor: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Contributing

## Contributing to the project

Contributions are welcome, NixOS expertise is recommended to ease integration.
Check open issues and the [contribution guide](./docs.md#building-the-documentation) to participate.
You can open tickets to propose features and discuss architecture.
AI-generated PRs without review and testing will be closed, further contributions from the same author may be blocked.

This README is in French in the source repository but code, issues and PRs are in English.

## Building the documentation

To build and render the documentation:
```
nix-build -A docs.all
xdg-open ./result/index.html
# or
xdg-open ./result/en/index.html  # English version
xdg-open ./result/fr/index.html  # French version
```
