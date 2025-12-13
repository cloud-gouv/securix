<!--
SPDX-FileCopyrightText: 2025 Ryan Lahfa <ryan.lahfa.ext@numerique.gouv.fr>

SPDX-License-Identifier: MIT
-->

# Sécurix: Base OS sécurisé pour poste d'administration

Ce projet est en **alpha**, aucun support n'est proposé pour l'heure.

## Objectifs

Sécurix est un projet développé et utilisé au département de l'opérateur (OPI) de la DINUM. 

Il constitue un modèle de PC sécurisé conçu pour permettre des accès à la production et d'autres usages critiques en garantissant un niveau de sécurité variable selon la configuration employée.

Grace à NixOS, ce modèle de PC sécurisé est ré-instantiable pour des cas d'usages variables: poste multi-agent, poste multi-niveaux, poste en intranet seulement, etc. avec des équipes différentes, des souches de VPN différents.

Construit selon les recommandations de l'ANSSI : <https://cyber.gouv.fr/publications/recommandations-relatives-ladministration-securisee-des-si>.

## Cible d'architecture technique

### Système d'exploitation

Sécurix repose sur NixOS avec un noyau Linux personnalisé conformément aux règles ANSSI de durcissement, certains d'entre eux étant désactivables selon le besoin.

### Modules de sécurité intégrés

- Configuration systématique selon les recommandations de l'ANSSI pour les systèmes GNU/Linux : <https://cyber.gouv.fr/publications/recommandations-de-securite-relatives-un-systeme-gnulinux>.
- Support avancé de TPM2 et Yubikey pour la gestion des clés d'authentification.
- Chiffrement des données à l'aide de `age` ou d'un serveur Vault.
- Enrôlement centralisé pour Secure Boot avec gestion PK/KEK.
- Connexion au poste de travail en FIDO2 et le mot de passe n'est qu'un mode secours.
- Déchiffrement du poste à l'aide d'une clé FIDO2 (une clé de secours est généré à l'installation). 

## Fonctionnalités en développement (par priorité)

- **Renforcement de la sécurité**
  - Application des recommandations ANSSI pour un durcissement complémentaire: <https://cyber.gouv.fr/publications/recommandations-de-securite-relatives-un-systeme-gnulinux>.
  - Ajout de la configuration d'un puits de traces pour l'envoi des activités d'un système Sécurix.
  
- **Onboarding rapide et gestion centralisée**
  - Mise en place d'un serveur "phone home" permettant d'ajouter automatiquement :
    - La clé SSH TPM2 du système au dépôt d'infrastructure.
    - L'autorisation pour déchiffrer les secrets via `age` (ou intégration future avec Vault).
    - Ce morceau d'infrastructure pourra s'insérer dans un processus métier visant à mettre en place un nouveau Sécurix pour un agent.

- **Support avancé des clés de sécurité**
  - Gestion et rotation des clés Secure Boot avec TPM2 pour renforcer Secure Boot.

## Contribuer

Les contributions sont les bienvenues ! Consultez les issues ouvertes et le guide de contribution pour participer.

## Licence

Sécurix est distribué sous licence MIT. Voir le fichier `LICENSE` pour plus de détails.
