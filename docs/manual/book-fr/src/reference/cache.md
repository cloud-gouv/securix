<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Un cache pour vos pipelines CI/CD (internes)

Ce document décrit comment configurer un **cache binaire Nix** dans un pipeline CI/CD pour réutiliser les résultats de compilation entre les exécutions et les machines.
Utiliser un cache réduit drastiquement les temps de compilation et la charge sur votre CI lors de la construction d'artefacts Sécurix (ISOs, configurations système, etc.).

Les exemples sont volontairement **agnostiques de la CI**. Quand un outillage spécifique à GitHub Actions est mentionné, nous expliquons comment le remplacer dans d'autres CI.

## Flux haut niveau du pipeline

Un pipeline CI utilisant un cache Nix suit généralement ces étapes :

1. Cloner le dépôt
2. Installer Nix (Sécurix est développé et testé avec https://lix.systems/)
3. Configurer l'accès au cache (substituters + identifiants)
4. Lancer `nix-build`, `nix develop` ou `nix build`
5. Envoyer les résultats vers le cache

Chacune de ces étapes est décrite ci-dessous.

> Note : le garbage collection n'est pas couvert ici. Après un certain temps, votre cache S3 accumulera des chemins Nix inutiles.
> Vous pouvez lancer un pipeline planifié pour expirer les objets selon la date ou leur vivacité avec des outils S3 standards.

## Étape 1 : Cloner le dépôt

Votre CI doit récupérer le code source avant de lancer les commandes Nix.

Aucune configuration spécifique à Nix n'est requise ici.

## Étape 2 : Installer Nix

Un interpréteur Nix doit être installé sur le runner CI.

### Prérequis

* Linux ou macOS
* Accès root ou sudo (sauf Nix en mode utilisateur, non recommandé)

### Options d'installation génériques

Vous pouvez installer Lix avec (exemple Linux) :

```sh
curl -L https://install.lix.systems/lix/lix-installer-x86_64-linux | sh
```

Après installation, vérifiez :

```sh
nix --version
```

### Remarques

Beaucoup de CI proposent des workflows réutilisables pour installer Nix.
Ils :

- préconfigurent `nix.conf` pour les entrées `nixpkgs`
- injectent les jetons de forge (GitHub, GitLab, etc.) pour éviter les limites d'API
- activent des fonctionnalités optionnelles comme l'accélération KVM

Si vous utilisez GitHub Actions, nous recommandons
<https://github.com/samueldr/lix-gha-installer-action>, rapide, léger et facile à auditer. Sa logique est portable vers d'autres CI.

## Étape 3 : Configurer le cache binaire

C'est l'étape la plus importante, et souvent la plus complexe.

### Configurer les substituters

Un substituter indique à Nix où télécharger les artefacts cachés.

Exemple :

```
s3://oss-securix
```

Avec paramètres additionnels :

* `endpoint` : endpoint S3 compatible
* `region` : région du stockage objet
* `compression` : format de compression. Nous recommandons `zstd` plutôt que `xz` : `zstd` offre une compression/décompression bien plus rapide pour un compromis taille raisonnable.
* `parallel-compression` : optimisation vitesse pour `xz` ou `zstd`

Ces réglages peuvent être appliqués via :

* `nix.conf`
* variables d'environnement
* drapeaux CLI

Exemple `nix.conf` :

```conf
substituters = https://cache.nixos.org s3://oss-securix?endpoint=https://s3.gra.io.cloud.ovh.net&region=gra
trusted-public-keys = oss-securix-1:PUBLIC_KEY_HERE
```

## Étape 4 : Configurer les secrets

Pour envoyer des artefacts vers le cache, Nix doit **signer** et avoir l'accès en écriture au stockage S3.

### Secrets requis

Stockez en secrets CI :

* **Clé privée de signature Nix** : générable via `nix key generate-secret`
* **Access key du stockage objet**
* **Secret key du stockage objet**

Si votre projet accepte des PR non fiables, séparez les caches :

- **Cache CI non fiable** : builds déclenchés par PR/forks
- **Cache CD fiable** : builds après merge/approbation

Cela évite que du code non revu pollue les caches fiables.

### Déclarer les secrets en CI

La plupart des CI supportent les secrets masqués, préférez ce mécanisme à un autre pouvant exposer les identifiants.

La clé de signature est typiquement référencée dans `nix.conf` :

```conf
secret-key-files = /path/to/signing-key
```

## Étape 5 : Activer l'envoi vers le cache

Pour que les résultats soient envoyés :

* Le cache doit être listé comme substituter
* La clé de signature doit être disponible
* Le job CI doit avoir l'accès en écriture au stockage objet
* Une partie de votre workflow doit envoyer les chemins

Pour ce dernier point, plusieurs solutions :

- Utiliser un `post-build-hook` pour envoyer immédiatement. Cela garantit que **tous** les chemins touchés sont envoyés, y compris ceux copiés depuis <https://cache.nixos.org>.
- envoyer manuellement avec `nix copy $built_path s3://your-bucket?endpoint=...` à la fin
- lancer un daemon observant le filesystem et copiant les chemins au fil de la construction

## Étape 6 : Lancer la compilation

Une fois tout configuré, lancez comme d'habitude :

```sh
nix-build -A tests
```

## Considérations de sécurité

* Ne jamais committer de clé privée
* Limiter les identifiants au minimum requis (lecture/écriture)
* Utiliser des caches séparés pour builds fiables/non fiables si nécessaire
* Restreindre qui peut envoyer vers le cache
* Supprimer l'accès direct à la clé de signature et aux identifiants S3 est possible via un service intermédiaire comme [Attic](https://github.com/zhaofengli/attic).
