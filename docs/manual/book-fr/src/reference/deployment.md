<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Options de déploiement

La plupart de ces méthodes sont des idées d'architecture, l'implémentation par défaut est la première.

Bureautix implémente la plupart des suivantes.

## 1. Installateur USB pour chaque système

Cette méthode consiste à créer un installateur USB distinct pour chaque système.
Chaque clé contient les fichiers d'installation adaptés à la configuration spécifique du système.

Lorsque l'utilisateur démarre depuis cette clé, l'installateur installe directement une closure NixOS spécifique après l'invocation de `autoinstall-terminal`.

Cette méthode est pratique lorsque vous avez peu de systèmes et pas d'infrastructure, c'est la méthode par défaut.

## 2. Installateur USB générique « masse »

L'installateur USB « masse » est conçu pour simplifier le déploiement de plusieurs systèmes. Il contient une liste de systèmes pré-configurés, chacun indexé par son numéro de série. Au démarrage, le système vérifie son numéro de série et sélectionne automatiquement la configuration appropriée. Vous pouvez ainsi avoir un seul installateur USB pour plusieurs systèmes.

Cette méthode est pratique pour installer en masse plusieurs systèmes en série. Elle nécessite une grosse clé USB si les systèmes ont beaucoup de personnalisations distinctes conduisant à de grosses closures.

Cette méthode est implémentée comme [exemple dans Bureautix](https://github.com/cloud-gouv/bureautix-example/blob/main/default.nix#L188-L212).

## 3. Installateur USB générique en ligne

L'installateur USB générique en ligne fonctionne comme l'installateur masse, mais se connecte à un site externe pendant l'installation. Au démarrage, le système envoie son numéro de série au site, qui redirige vers une closure NixOS adaptée à ce numéro.

Le site cible doit agir comme un cache Nix, une fois la redirection effectuée, Nix copie la closure en mémoire.

Cette méthode est pratique lorsque les configurations sont toutes construites en CI et poussées vers un cache accessible dans l'environnement de l'installateur. La clé USB peut être gravée une fois et reste relativement à jour tant que le partitionnement ou les fonctions de boot spéciales ne changent pas.

Cette méthode peut être implémentée à partir [d'un exemple dans Bureautix](https://github.com/cloud-gouv/bureautix-example/blob/main/default.nix#L188-L212) en ajoutant d'autres closures.

## 4. Installation par netboot

L'installation par netboot est une solution légère où l'installateur est envoyé via PXE au lieu d'une clé USB physique. Au démarrage, le système récupère l'installateur par le réseau (HTTP ou TFTP) et télécharge les fichiers nécessaires. Cela permet d'installer sans support physique.

Cette méthode est pratique pour les cycles de développement, le déploiement de masse sur site et même en ligne si votre OEM supporte le HTTP boot et que vous avez un mécanisme d'authentification du système d'origine.

Cette méthode est implémentée comme [exemple dans Bureautix](https://github.com/cloud-gouv/bureautix-example/tree/main/netboot).
