<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Prise en main rapide

## 1. Copier le squelette

Pour commencer, copiez le fichier `default.nix` squelette fourni dans le répertoire [examples/basic](../../../examples/basic).

## 2. Créer les utilisateurs et l'inventaire

Créez ensuite votre inventaire système. Vous pouvez vous inspirer de la structure d'exemple fournie par Bureautix ici : [inventaire d'exemple Bureautix](https://github.com/cloud-gouv/bureautix-example/tree/main/inventory).

Dans votre inventaire, vous pouvez organiser les éléments en deux sections principales : *machines* et *utilisateurs*. Chaque machine peut avoir une liste d'utilisateurs assignés.

## 3. Personnaliser votre système

À ce stade, vous pouvez personnaliser votre système NixOS. Vous avez deux options :

* Utiliser les modules fournis par Sécurix, tels que `securix.firefox` pour la configuration de Firefox.
* Ou utiliser des modules NixOS standards pour la personnalisation du système.

## 4. Déployer l'installateur USB

Sécurix fournit un ensemble d'attributs par défaut pour chaque terminal :

* `installer` : un installateur USB spécifique au terminal. Démarrer depuis cette clé USB fournit la commande `autoinstall-terminal` pour installer automatiquement le système.
* `system` : l'attribut NixOS de plus haut niveau, utile pour les options de déploiement avancées.
