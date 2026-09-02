<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Déclarer outils et programmes

La déclaration d'outils ou de programme se fait en utilisant les options NixOS classiques, e.g. `environment.systemPackages`.

## Déclarer un outil pour l'ensemble des utilisateurs du poste

Dans le fichier `common/tools.nix`, il est possible d'ajouter un paquet pour tout le monde.

## Déclarer un outil pour un sous-ensemble des utilisateurs du poste

Dans le fichier `common/tools.nix`, il est possible d'ajouter un paquet conditionnellement relatif à quel est le poste ou l'utilisateur en inspectant `config.securix.self.user` ou `config.securix.self.machine`.

## Déclarer un outil pour une personne

Dans le fichier d'inventaire, il est possible d'ajouter `environment.systemPackages` sur une machine ou sur une personne.
