<!--
SPDX-FileCopyrightText: 2026 Antoine Eiche <antoine.eiche@lewocorp.eu>
SPDX-FileContributor: 2026 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Comment contribuer

## Contribuer au projet

Les contributions sont ouvertes au projet, il est recommandé d'avoir une expertise NixOS pour en faciliter l'intégration.
Consultez les tickets ouverts et le [guide de contribution](./docs.md#compiler-la-documentation) pour participer.
Vous pouvez ouvrir des tickets pour proposer des fonctionnalités et discuter de l'architecture.
Les PR générées par IA sans relecture ni test seront fermées, les contributions par le même auteur pourront être bloquées par la suite.

Ce README est en français mais le reste du code, les *issues* et les PR sont en anglais.

## Compiler la documentation

Pour compiler et afficher la documentation :
```
nix-build -A docs.all
xdg-open ./result/index.html
# ou
xdg-open ./result/en/index.html  # version anglaise
xdg-open ./result/fr/index.html  # version française
```
