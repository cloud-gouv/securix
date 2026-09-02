<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Gérer l'inventaire statique : ajout et suppressions

Le projet SécurixOS ne supporte officiellement pour le moment que les inventaires statiques qui conviennent aux environnements jusqu'à 300 utilisateurs. Au delà, il est possible d'utiliser des inventaires statiques mais il convient de mettre en place des techniques de gestion à l'échelle, i.e. générer l'inventaire statique depuis une base de données ITSM, de fractionner les repertoires d'inventaires par rapport à des préfixes distinguants pour éviter d'avoir trop de fichiers dans le même repertoire et ainsi de suite.

Le projet SécurixOS prévoit de supporter les inventaires dynamiques reposant sur LDAP ou OIDC, ce qui éliminerait le besoin de prédéclarer les utilisateurs dans Git.

## Comment ajouter une nouvelle machine ?

Pour ajouter une nouvelle machine, il suffit d'ajouter un nouveau fichier `.nix` avec le nom de son identifiant (e.g. numéro de série, asset tag, numéro d'inventaire interne) avec le contenu suivant :

```nix
{
  securix.self.mainDisk = "/dev/nvme0n1"; # Si c'est un disque NVMe, sinon /dev/sda si c'est un disque sur le bus SATA.
  securix.self.machine = {
    hardwareSKU = "x280"; # Le SKU pour le profil matériel, ici: X280.
    serialNumber = "PC140V35"; # Le numéro de série, d'asset tag ou d'inventaire interne du système, il est utilisé pour construire le nom d'hôte de la machine.

    users = [
      "heloise" # Les utilisateurs qui seront provisionnés sur cette machine. Il faut qu'ils existent au préalable.
    ];
  };
}
```

## Comment ajouter une nouvelle personne ?

Pour ajouter une nouvelle personne, il suffit d'ajouter un nouveau fichier `.nix` avec son identifiant utilisateur (prénom, prénom puis nom, etc.) :

```nix
{ pkgs, ... }:
{
  securix.self.user = {
    email = "heloise@example.com"; # Adresse email
    username = "heloise"; # Nom d'utilisateur
    # password is `test`
    hashedPassword = "$y$j9T$zk4xGLyshz7RzqnMX6M8O0$AybRelILMkQSWcQZV4s.ykRNi/UlgaCUaDwdee0n7N2"; # Mot de passe hashés avec ycrypt
    defaultLoginShell = pkgs.zsh; # Optionnellement, shell pour l'utilisateur
  };
}
```

> ⚠️ Attention, ces fichiers Nix ne vivent pas dans un module NixOS pour les développeurs qui connaissent bien NixOS, ceci est une limitation documentée par <https://github.com/cloud-gouv/securix/issues/196> que nous souhaitons lever.

L'ensemble des options configurables sur un utilisateur sont disponibles à <https://github.com/cloud-gouv/securix/blob/main/modules/self.nix#L74-L140>.
