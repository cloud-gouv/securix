<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>
SPDX-FileContributor: 2026 Xavier Maso <xavier.maso@beta.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Qu'est-ce que Sécurix ?

Un système d'exploitation développé à la [DINUM](https://www.numerique.gouv.fr/), principalement pour un usage interne, pour construire des environnements de poste de travail déclaratifs, reproductibles et sécurisés par défaut.
Basé sur [`NixOS`](https://nixos.org/), il permet d'écrire la configuration sous forme de code pour définir les utilisateurs, programmes, services, configurations, et plus encore.

> [!NOTE]
> Ce projet est en **alpha**, aucun support n'est proposé pour l'heure.

## Objectifs

SécurixOS est une distribution NixOS développée par la DINUM pour équiper des ordinateurs sécurisés pour l'administration système, la bureautique et le développement afin de traiter des informations Non Protégées dans un premier temps puis éventuellement des informations Diffusion Restreinte.

Il constitue un modèle de PC sécurisé conçu pour permettre des accès à la production et d'autres usages critiques en garantissant un niveau de sécurité variable selon la configuration employée.

Grâce à NixOS, ce modèle est ré-instantiable pour des cas d'usages variables : poste multi-agent, poste multi-niveaux, poste en intranet seulement, etc. avec des équipes différentes, des souches de VPN différents.

Construit selon les recommandations de l'ANSSI : <https://cyber.gouv.fr/publications/recommandations-relatives-ladministration-securisee-des-si>.

## Licences

Sécurix est distribué sous licence [MIT](https://github.com/cloud-gouv/securix/blob/main/LICENSES/MIT.txt). Voir le dossier `LICENSES` pour plus de détails.
Voir aussi [Comment contribuer](../contributor/docs.md).
